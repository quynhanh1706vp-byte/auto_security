#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TS="$(date +%Y%m%d_%H%M%S)"
echo "[ROOT] $(pwd)"
echo "[TS]   $TS"

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] not found: $APP"; exit 1; }

cp "$APP" "$APP.bak_runv1_beforemain_${TS}"
echo "[BACKUP] $APP.bak_runv1_beforemain_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# remove any previous blocks (avoid duplicates)
txt = re.sub(r'(?s)\n# === VSP_RUN_API_BLUEPRINT_V1 ===.*?# === END VSP_RUN_API_BLUEPRINT_V1 ===\n', "\n", txt)

block = r'''
# === VSP_RUN_API_BLUEPRINT_V1 ===
try:
    from run_api.vsp_run_api_v1 import bp_vsp_run_api_v1
    app.register_blueprint(bp_vsp_run_api_v1)
    print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>", flush=True)
except Exception as e:
    print("[VSP_RUN_API] ERR register blueprint:", repr(e), flush=True)
# === END VSP_RUN_API_BLUEPRINT_V1 ===
'''

# insert BEFORE main guard if exists
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt)
if m:
    txt = txt[:m.start()] + block + "\n" + txt[m.start():]
else:
    # fallback: insert before first app.run(
    m2 = re.search(r'(?m)^\s*app\.run\(', txt)
    if m2:
        txt = txt[:m2.start()] + block + "\n" + txt[m2.start():]
    else:
        # last resort: put near top after app=Flask(...)
        m3 = re.search(r'(?m)^\s*app\s*=\s*Flask\([^\n]*\)\s*$', txt)
        if m3:
            txt = txt[:m3.end()] + "\n" + block + "\n" + txt[m3.end():]
        else:
            txt += "\n" + block + "\n"

p.write_text(txt, encoding="utf-8")
print("[OK] inserted blueprint register block BEFORE app.run/main")
PY

python3 -m py_compile "$APP"
echo "[OK] vsp_demo_app.py syntax OK"

# restart
pkill -f vsp_demo_app.py || true
mkdir -p out_ci
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "[OK] restarted UI"
tail -n 40 out_ci/ui_8910.log || true

echo
echo "== CHECK 1: should NOT be 404 =="
# GET may return 405; 404 is wrong.
curl -s -o /dev/null -w "GET /api/vsp/run_v1 -> HTTP_CODE=%{http_code}\n" http://localhost:8910/api/vsp/run_v1 || true

echo
echo "== CHECK 2: log should show VSP_RUN_API =="
grep -n "VSP_RUN_API" -n out_ci/ui_8910.log | tail -n 10 || true
