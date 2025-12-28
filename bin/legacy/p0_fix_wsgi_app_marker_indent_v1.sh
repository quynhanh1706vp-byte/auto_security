#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need awk; need grep; need nl

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_indentfix_${TS}"
echo "[BACKUP] ${F}.bak_indentfix_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# Remove previous injected blocks (v2 + v1 style)
s = re.sub(r'(?ms)^[ \t]*# --- VSP_P0_ALIAS_APP_TO_APPLICATION_BEFORE_DECORATORS_V2 ---.*?^[ \t]*# --- end VSP_P0_ALIAS_APP_TO_APPLICATION_BEFORE_DECORATORS_V2 ---\n\n?', '', s)
s = re.sub(r'(?ms)^[ \t]*# --- VSP_P0_DEFINE_APP_BEFORE_DECORATORS_V1 ---.*?^[ \t]*# --- end VSP_P0_DEFINE_APP_BEFORE_DECORATORS_V1 ---\n\n?', '', s)

m = re.search(r'(?m)^([ \t]*)@app\.[A-Za-z_]\w*', s)
if not m:
    print("[ERR] cannot find '@app.' decorator to anchor insertion")
    raise SystemExit(2)

indent = m.group(1)

marker = "VSP_P0_ALIAS_APP_TO_APPLICATION_BEFORE_DECORATORS_V3"
block = f"""# --- {marker} ---
# Ensure 'app' exists before any @app.* decorators (indent-safe).
try:
    app
except NameError:
    try:
        app = application  # prefer existing callable (gunicorn entrypoint)
    except Exception:
        from flask import Flask
        app = Flask(__name__)
        application = app

# Keep both names in sync
try:
    application
except NameError:
    application = app
# --- end {marker} ---

"""

# indent every non-empty line to match decorator indentation
indented = "\n".join((indent + line) if line.strip() else "" for line in block.splitlines()) + "\n"

s2 = s[:m.start()] + indented + s[m.start():]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted indent-safe alias block at first @app.* with indent repr=", repr(indent))
PY

echo "== [1] py_compile (show errors) =="
set +e
PYERR="$(python3 -m py_compile "$F" 2>&1)"
RC=$?
set -e
if [ "$RC" -ne 0 ]; then
  echo "[ERR] py_compile failed:"
  echo "$PYERR"
  # Try to extract line number and print context
  LINE="$(echo "$PYERR" | grep -Eo 'line [0-9]+' | head -n 1 | awk '{print $2}')"
  if [ -n "${LINE:-}" ]; then
    echo "== [context] around line $LINE =="
    START=$((LINE-25)); [ "$START" -lt 1 ] && START=1
    END=$((LINE+25))
    nl -ba "$F" | sed -n "${START},${END}p"
  fi
  exit 2
fi
echo "[OK] py_compile OK"

echo "== [2] import test =="
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

echo "== [3] restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 90 || true

echo "== [4] smoke curl =="
curl -fsS --connect-timeout 1 http://127.0.0.1:8910/runs >/dev/null && echo "[OK] /runs reachable" || echo "[ERR] /runs still not reachable"
