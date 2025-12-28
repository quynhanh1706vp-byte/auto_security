#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_define_app_${TS}"
echo "[BACKUP] ${F}.bak_define_app_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P0_DEFINE_APP_BEFORE_DECORATORS_V1"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

# Find first decorator usage of @app.*
m = re.search(r'(?m)^\s*@app\.[A-Za-z_]\w*', s)
if not m:
    print("[ERR] cannot find any '@app.' decorator to anchor insertion")
    raise SystemExit(2)

ins = f"""# --- {marker} ---
# Ensure 'app' exists before any @app.* decorators (gunicorn import safety)
try:
    app
except NameError:
    try:
        # if some code defined 'application' earlier, alias it
        app = application  # type: ignore[name-defined]
    except Exception:
        try:
            from flask import Flask
            app = Flask(__name__)
        except Exception as e:
            raise RuntimeError("VSP boot: cannot create Flask app") from e
# Keep gunicorn callable stable
try:
    application
except NameError:
    application = app
# --- end {marker} ---

"""

s2 = s[:m.start()] + ins + s[m.start():]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted define-app block before first @app.* decorator")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== import test =="
python3 - <<'PY'
import importlib, traceback
try:
    m=importlib.import_module("wsgi_vsp_ui_gateway")
    a=getattr(m,"app",None)
    b=getattr(m,"application",None)
    print("import OK")
    print("app:", type(a).__name__, "callable=", callable(a))
    print("application:", type(b).__name__, "callable=", callable(b))
except Exception as e:
    print("import FAIL:", e)
    traceback.print_exc()
    raise
PY

echo "== restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 90 || true

echo "[NEXT] If service is ACTIVE, run: bash bin/p1_ui_spec_gate_v1.sh"
