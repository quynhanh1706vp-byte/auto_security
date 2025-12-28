#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Missing: $TPL"
  exit 1
fi

BK="${TPL}.bak_runscan_switch_v2_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BK"
echo "[BACKUP] $BK"

# remove v1 tag (if any), add v2 tag
sed -i \
  -e 's#/static/js/vsp_runs_trigger_scan_ui_v1\.js#/static/js/vsp_runs_trigger_scan_ui_v2.js#g' \
  "$TPL"

# if v1 tag existed but with different spacing, ensure v2 appears at least once
if ! grep -q 'vsp_runs_trigger_scan_ui_v2\.js' "$TPL"; then
  TAG='<script src="/static/js/vsp_runs_trigger_scan_ui_v2.js" defer></script>'
  sed -i "s#</body>#  ${TAG}\n</body>#g" "$TPL"
fi

echo "[OK] switched to v2"
