#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need awk; need sed; need curl; need python3; need pgrep; need pkill; need sleep; need tail; need grep; need nohup; need kill

BASE="http://127.0.0.1:8910"
PAT_ANY="gunicorn.*wsgi_vsp_ui_gateway:application.*--bind .*:8910"

pids_listen_8910() {
  # extract PIDs from ss users:(("gunicorn",pid=2483,fd=5),...)
  ss -ltnp 2>/dev/null | awk '
    /:8910/ && /users:\(\(/ {
      line=$0
      while (match(line, /pid=[0-9]+/)) {
        pid=substr(line, RSTART+4, RLENGTH-4)
        print pid
        line=substr(line, RSTART+RLENGTH)
      }
    }' | sort -u
}

echo "== who is listening :8910 (before) =="
ss -ltnp 2>/dev/null | grep ':8910' || true
echo "PIDS=$(pids_listen_8910 | tr '\n' ' ' | sed 's/[[:space:]]\+$//')"

echo "== kill anything listening on :8910 (TERM) =="
for pid in $(pids_listen_8910); do
  echo " - kill -TERM $pid"
  kill -TERM "$pid" 2>/dev/null || true
done

echo "== also pkill by pattern (safety net) =="
pkill -f "$PAT_ANY" || true
rm -f /tmp/vsp_ui_8910.lock || true

echo "== wait port free =="
for i in $(seq 1 160); do
  if ss -ltnp 2>/dev/null | grep -q ':8910'; then
    sleep 0.15
  else
    break
  fi
done

if ss -ltnp 2>/dev/null | grep -q ':8910'; then
  echo "[WARN] still listening after TERM; escalating KILL"
  ss -ltnp 2>/dev/null | grep ':8910' || true
  for pid in $(pids_listen_8910); do
    echo " - kill -KILL $pid"
    kill -KILL "$pid" 2>/dev/null || true
  done
  sleep 0.3
fi

if ss -ltnp 2>/dev/null | grep -q ':8910'; then
  echo "[ERR] port :8910 still in use; refusing to start a second owner"
  ss -ltnp 2>/dev/null | grep ':8910' || true
  exit 4
fi

echo "== start gunicorn :8910 (ui/.venv) =="
[ -x .venv/bin/gunicorn ] || { echo "[ERR] missing ui/.venv/bin/gunicorn"; exit 2; }
mkdir -p out_ci
: > out_ci/ui_8910.boot.log || true
nohup .venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== wait READY (runs JSON) =="
RID=""
for i in $(seq 1 240); do
  if ! ss -ltnp 2>/dev/null | grep -q ':8910'; then
    sleep 0.15
    continue
  fi

  R="$(curl -fsS --max-time 2 --retry 3 --retry-delay 0 --retry-connrefused \
        "$BASE/api/vsp/runs?limit=1" 2>/dev/null || true)"
  if [ -n "${R:-}" ]; then
    RID="$(python3 - <<'PY' 2>/dev/null || true
import json,sys
try:
  o=json.loads(sys.stdin.read())
  items=o.get("items") or []
  print(items[0].get("run_id","") if items else "")
except Exception:
  print("")
PY
<<<"$R")"
    if [ -n "${RID:-}" ]; then
      echo "[OK] READY rid=$RID"
      break
    fi
  fi
  sleep 0.15
done

if [ -z "${RID:-}" ]; then
  echo "[ERR] not READY in time; last logs:"
  tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
  tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
  exit 5
fi

echo "== verify dash endpoints =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 220; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 220; echo

echo "== done (pids/port) =="
pgrep -af "$PAT_ANY" || true
ss -ltnp | grep ':8910' || true
