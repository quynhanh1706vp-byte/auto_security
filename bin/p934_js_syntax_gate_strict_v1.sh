#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node

FILES=(
  "static/js/vsp_c_settings_v1.js"
  "static/js/vsp_ops_panel_v1.js"
  "static/js/vsp_c_sidebar_v1.js"
  "static/js/vsp_c_runs_v1.js"
  "static/js/vsp_data_source_tab_v3.js"
)

echo "== [P934] JS syntax STRICT gate =="
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "[FAIL] missing: $f"
    exit 3
  fi
  if node --check "$f" >/dev/null 2>&1; then
    echo "[OK] $f"
  else
    echo "[FAIL] js syntax: $f"
    node --check "$f" || true
    exit 4
  fi
done
echo "[OK] P934 gate PASS"
