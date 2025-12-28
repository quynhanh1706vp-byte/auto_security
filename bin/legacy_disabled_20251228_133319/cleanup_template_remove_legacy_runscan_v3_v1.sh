#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$TPL.bak_rm_runscanv3_${TS}"
echo "[BACKUP] $TPL.bak_rm_runscanv3_${TS}"

# remove legacy runscan ui v3 tag
sed -i '/vsp_runs_trigger_scan_ui_v3\.js/d' "$TPL"

echo "[OK] removed vsp_runs_trigger_scan_ui_v3.js tag"
grep -n "vsp_runs_trigger_scan_ui_v3.js" -n "$TPL" || true
