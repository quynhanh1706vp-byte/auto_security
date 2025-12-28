#!/usr/bin/env bash
set -euo pipefail
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$TPL.bak_rm_runscan_hook_${TS}"
echo "[BACKUP] $TPL.bak_rm_runscan_hook_${TS}"

# Remove legacy hook (mount hook) + any legacy runscan ui (defensive)
sed -i '/vsp_runs_trigger_scan_mount_hook_v1\.js/d' "$TPL"
sed -i '/vsp_runs_trigger_scan_ui_v3\.js/d' "$TPL"

echo "[OK] removed legacy runscan hook + legacy ui v3 tags (if existed)"
