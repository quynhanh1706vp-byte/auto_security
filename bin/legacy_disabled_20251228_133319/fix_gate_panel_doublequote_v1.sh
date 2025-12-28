#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_gate_panel_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_fixdq_${TS}" && echo "[BACKUP] $F.bak_fixdq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# Fix the exact bad token: ""/api...  -> "/api...
s2 = s.replace('""/api/vsp/', '"/api/vsp/')

# Also handle any accidental ""/api... in file
s2 = s2.replace('""/api/', '"/api/')

# Guard: avoid creating triple quotes
s2 = re.sub(r'""+"/api', '"/api', s2)

if s2 == s:
    print("[WARN] no double-quote pattern found (maybe already fixed)")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed double-quote before /api in gate panel")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

# restart 8910
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.0
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] Hard refresh Ctrl+Shift+R, check CI/CD Gate panel"
