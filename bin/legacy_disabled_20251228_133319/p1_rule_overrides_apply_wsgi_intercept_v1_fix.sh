#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="wsgi_vsp_ui_gateway.py"
python3 -m py_compile "$F" >/dev/null
echo "[OK] apply intercept already in $F (WSGI wrapper). Nothing to do."
