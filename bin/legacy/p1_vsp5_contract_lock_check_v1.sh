#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need head

H="$(curl -sS "$BASE/vsp5" || true)"
echo "$H" | grep -q "vsp_tabs4_autorid_v1.js?v=" || { echo "[ERR] /vsp5 missing tabs js"; exit 2; }
echo "$H" | grep -q "vsp_topbar_commercial_v1.js?v=" || { echo "[ERR] /vsp5 missing topbar js"; exit 2; }
echo "$H" | grep -qE 'vsp_tabs4_autorid_v1\.js\?v=[0-9]+' || { echo "[ERR] /vsp5 tabs js missing numeric v"; exit 2; }
echo "[OK] /vsp5 contract locked (tabs+topbar present with numeric v=)"
