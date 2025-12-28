#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
B="$(cat out_ci/KNOWN_GOOD_WSGI.txt)"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }
cp -f "$B" wsgi_vsp_ui_gateway.py
python3 -m py_compile wsgi_vsp_ui_gateway.py
sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"
