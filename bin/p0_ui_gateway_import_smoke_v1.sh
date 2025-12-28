#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PY="python3"
if [ -x ".venv/bin/python" ]; then PY=".venv/bin/python"; fi

echo "== PY=$PY =="
$PY -V

echo "== import module =="
$PY - <<'PY'
import traceback
try:
    import wsgi_vsp_ui_gateway as m
    print("[OK] import wsgi_vsp_ui_gateway")
    app = getattr(m, "application", None)
    print("[OK] application:", type(app), app)
except Exception as e:
    print("[ERR] import/load failed:", repr(e))
    traceback.print_exc()
    raise
PY
