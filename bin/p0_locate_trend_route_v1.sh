#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need grep; need sed; need awk

echo "== locate trend_v1 references =="
grep -RIn --line-number "/api/vsp/trend_v1" \
  wsgi_vsp_ui_gateway.py vsp_demo_app.py ui/vsp_demo_app.py 2>/dev/null || true

echo
echo "== locate functions likely serving trend =="
grep -RIn --line-number -E "def\s+.*trend|trend_v1" \
  wsgi_vsp_ui_gateway.py vsp_demo_app.py ui/vsp_demo_app.py 2>/dev/null || true

echo "[DONE]"
