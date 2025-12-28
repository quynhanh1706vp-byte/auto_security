#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
BASE="http://127.0.0.1:${PORT}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need systemctl
need ss
need python3
command -v curl >/dev/null 2>&1 || true
command -v ps >/dev/null 2>&1 || true

echo "== [1] restart service clean =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
sudo systemctl status "$SVC" -n 12 --no-pager || true

echo "== [2] get service ControlGroup =="
CG="$(sudo systemctl show "$SVC" -p ControlGroup --value | tr -d '\r' || true)"
echo "[INFO] ControlGroup=$CG"

echo "== [3] find listener PIDs on :$PORT =="
ss -lptn "sport = :$PORT" || true

PIDS="$(python3 - <<'PY'
import subprocess, re
out = subprocess.check_output(["ss","-lptn",f"sport = :{8910}"], text=True, errors="replace")
pids = sorted(set(int(x) for x in re.findall(r'pid=(\d+)', out)))
print(" ".join(map(str,pids)))
PY
)"
echo "[INFO] listener_pids=(${PIDS})"

if [ -z "${PIDS// }" ]; then
  echo "[WARN] no listener found on :$PORT"
else
  echo "== [4] classify PIDs: in-service vs stray (by /proc/PID/cgroup contains ControlGroup) =="
  STRAY=""
  for p in $PIDS; do
    if [ -n "$CG" ] && sudo cat "/proc/$p/cgroup" 2>/dev/null | grep -qF "$CG"; then
      echo "[OK] in-service pid=$p"
    else
      echo "[WARN] STRAY pid=$p"
      ps -p "$p" -o pid,ppid,etime,cmd || true
      STRAY="$STRAY $p"
    fi
  done

  if [ -n "${STRAY// }" ]; then
    echo "== [5] kill STRAY listeners (TERM then KILL) =="
    for p in $STRAY; do sudo kill -TERM "$p" 2>/dev/null || true; done
    sleep 1
    for p in $STRAY; do
      if sudo kill -0 "$p" 2>/dev/null; then
        sudo kill -KILL "$p" 2>/dev/null || true
      fi
    done
    sleep 1
  else
    echo "[OK] no stray listeners"
  fi
fi

echo "== [6] ensure service is the only owner: restart once more =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
ss -lptn "sport = :$PORT" || true

echo "== [7] smoke =="
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 220; echo || true

echo "[DONE] v24f"
