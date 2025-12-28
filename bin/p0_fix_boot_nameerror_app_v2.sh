#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need tail; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
VENV_PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
[ -x "$VENV_PY" ] || VENV_PY="python3"

echo "== [0] stop + reset-failed (avoid restart storm) =="
systemctl stop "$SVC" || true
systemctl reset-failed "$SVC" || true

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_app_${TS}"
echo "[BACKUP] ${F}.bak_fix_app_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_ALIAS_APP_TO_APPLICATION_BEFORE_DECORATORS_V2"
if marker in s:
    print("[OK] marker already present, skip patch")
    raise SystemExit(0)

# Find the first decorator @app.*
m = re.search(r'(?m)^[ \t]*@app\.[A-Za-z_]\w*', s)
if not m:
    print("[ERR] no @app.* decorator found (unexpected)"); raise SystemExit(2)

ins = f"""# --- {marker} ---
# Fix: ensure 'app' exists before any @app.* decorators.
# Prefer aliasing to existing Flask instance 'application' (gunicorn entrypoint).
try:
    app
except NameError:
    try:
        app = application  # type: ignore[name-defined]
    except Exception:
        # last-resort fallback (only if both names absent)
        from flask import Flask
        app = Flask(__name__)
        application = app
# keep both names in sync
try:
    application
except NameError:
    application = app
# --- end {marker} ---

"""

s2 = s[:m.start()] + ins + s[m.start():]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted alias block before first @app.*")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== [1] import test (venv python) =="
"$VENV_PY" - <<'PY'
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

echo "== [2] start service =="
systemctl start "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 90 || true

echo "== [3] tail gunicorn error log =="
if [ -f "$ERRLOG" ]; then
  tail -n 120 "$ERRLOG" || true
else
  echo "[WARN] missing $ERRLOG"
fi

echo "== [4] smoke curl =="
curl -fsS --connect-timeout 1 http://127.0.0.1:8910/runs >/dev/null && echo "[OK] /runs reachable" || echo "[ERR] /runs still not reachable"
