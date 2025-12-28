#!/usr/bin/env bash
set -euo pipefail

TPL="templates/vsp_dashboard_2025.html"

if ! grep -q "vsp_runs_trigger_scan_v1.js" "$TPL"; then
    echo "[PATCH] Adding vsp_runs_trigger_scan_v1.js to template..."
    sed -i '/<\/body>/i \
    <script src="/static/js/vsp_runs_trigger_scan_v1.js" defer></script>' "$TPL"
else
    echo "[PATCH] Already exists."
fi
