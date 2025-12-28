#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/python -m pip -q install -U pip setuptools wheel >/dev/null
.venv/bin/python -m pip -q install -U flask flask-cors requests >/dev/null

pkill -f vsp_demo_app.py || true
mkdir -p out_ci
nohup .venv/bin/python -u vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "PY=$(.venv/bin/python -c 'import sys; print(sys.executable)')"
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://localhost:8910/ || true

# === VSP_START_8910_WAITLOOP_V1 ===
# Wait up to 10s for port to open; if fail, print last traceback lines.
ok="0"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sS -o /dev/null "http://localhost:8910/" ; then
    ok="1"
    break
  fi
  sleep 1
done

if [ "$ok" != "1" ]; then
  echo "[ERR] 8910 not responding after 10s. Showing last 120 lines of out_ci/ui_8910.log"
  tail -n 120 "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log" 2>/dev/null || true
  exit 1
fi
# === END VSP_START_8910_WAITLOOP_V1 ===

