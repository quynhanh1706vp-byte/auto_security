#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl

W="wsgi_vsp_ui_gateway.py"
python3 -m py_compile "$W"
echo "[OK] py_compile $W"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
