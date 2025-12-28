#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_reg_runapi_${TS}"
echo "[BACKUP] $F.bak_reg_runapi_${TS}"

# Ensure run_api is importable
mkdir -p run_api
[ -f run_api/__init__.py ] || echo "# run_api pkg" > run_api/__init__.py

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

block = r'''
# === VSP_RUN_API_REGISTER_FORCE_V1 ===
try:
    from run_api.vsp_run_api_v1 import bp as vsp_run_api_v1_bp
    app.register_blueprint(vsp_run_api_v1_bp)
    print("[VSP_RUN_API] registered blueprint v1 OK")
except Exception as e:
    print("[VSP_RUN_API] WARN: cannot register run_api blueprint:", e)
# === END VSP_RUN_API_REGISTER_FORCE_V1 ===
'''.lstrip("\n")

# If already inserted, do nothing
if "VSP_RUN_API_REGISTER_FORCE_V1" in txt:
    print("[OK] register block already exists")
    raise SystemExit(0)

# Find app = Flask(...) line
m = re.search(r'(?m)^\s*app\s*=\s*Flask\s*\(.*\)\s*$', txt)
if m:
    ins = m.end()
    txt = txt[:ins] + "\n\n" + block + "\n" + txt[ins:]
    print("[OK] inserted register block right after app = Flask(...)")
else:
    # Fallback: insert before if __name__ == "__main__"
    m2 = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt)
    if m2:
        ins = m2.start()
        txt = txt[:ins] + "\n" + block + "\n" + txt[ins:]
        print("[OK] inserted register block before __main__")
    else:
        txt = txt + "\n\n" + block + "\n"
        print("[OK] appended register block at EOF")

p.write_text(txt, encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] vsp_demo_app.py syntax OK"

# Restart UI
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== PS =="
ps aux | grep -E "vsp_demo_app.py" | grep -v grep || true

echo
echo "== LOG (last 40) =="
tail -n 40 out_ci/ui_8910.log || true

echo
echo "== SMOKE: /api/vsp/run_v1 must be 405 or 400, NOT 404 =="
curl -s -o /dev/null -w "HTTP_CODE=%{http_code}\n" http://localhost:8910/api/vsp/run_v1 || true
