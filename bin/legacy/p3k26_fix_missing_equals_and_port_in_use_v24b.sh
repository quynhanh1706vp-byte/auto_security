#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PORT=8910
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
PIDFILE="${OUT}/ui_${PORT}.pid"

F1="/etc/systemd/system/${SVC}.d/override.conf"
F2="/etc/systemd/system/${SVC}.d/zzzz-999-final.conf"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need python3
need systemctl
need ss
command -v awk >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

echo "== [1] stop service + reset-failed =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

echo "== [2] free port :$PORT (kill stray listeners) =="
ss -lptn "sport = :$PORT" || true
PIDS="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[WARN] killing PIDs holding $PORT: $PIDS"
  for p in $PIDS; do sudo kill -TERM "$p" 2>/dev/null || true; done
  sleep 1
  P2="$(ss -lptn "sport = :$PORT" 2>/dev/null | awk -F'pid=|,' '/pid=/{print $2}' | sort -u | tr '\n' ' ')"
  if [ -n "${P2// }" ]; then
    echo "[WARN] force kill: $P2"
    for p in $P2; do sudo kill -KILL "$p" 2>/dev/null || true; done
    sleep 1
  fi
fi
ss -lptn "sport = :$PORT" || true

echo "== [3] clean 'Missing =' lines in drop-ins (F1,F2) =="
sudo python3 - <<'PY'
from pathlib import Path
import re, shutil, time

files = [Path(r"/etc/systemd/system/%s.d/override.conf") , Path(r"/etc/systemd/system/%s.d/zzzz-999-final.conf")]
# We cannot format inside Path above without svc; read svc from systemd path by globbing later.
PY
# do it with bash vars instead (safer)
sudo python3 - "$F1" "$F2" <<'PY'
import sys, re, shutil, time
from pathlib import Path

section_ok=re.compile(r'^\s*\[(Unit|Service|Install)\]\s*$')
kv_ok=re.compile(r'^\s*[A-Za-z0-9][A-Za-z0-9_]*\s*=')

for fp in sys.argv[1:]:
    p=Path(fp)
    if not p.exists():
        print("[SKIP] missing", fp)
        continue
    s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)
    out=[]
    changed=False
    for ln in s:
        t=ln.strip()
        if t=="" or t.startswith("#") or section_ok.match(t) or kv_ok.match(t):
            out.append(ln); continue
        out.append("# P3K26_V24B_COMMENT_BAD_LINE: " + ln)
        changed=True
    if changed:
        bak=str(p)+f".bak_v24b_{int(time.time())}"
        shutil.copy2(p,bak)
        p.write_text("".join(out), encoding="utf-8")
        print("[OK] cleaned", fp, "backup", bak)
    else:
        print("[OK] no bad lines", fp)
PY

echo "== [4] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [5] verify + smoke =="
systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 50 || true
ss -lptn "sport = :$PORT" || true
curl -fsS --connect-timeout 1 --max-time 5 "http://127.0.0.1:${PORT}/api/vsp/rid_latest" | head -c 220; echo || true
echo "[DONE] v24b"
