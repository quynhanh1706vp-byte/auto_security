#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [A] JS parse check =="
JS_LIST=(
  static/js/vsp_runs_commercial_panel_v1.js
  static/js/vsp_dashboard_enhance_v1.js
  static/js/vsp_dashboard_charts_pretty_v3.js
  static/js/vsp_tabs_hash_router_v1.js
  static/js/vsp_runs_tab_resolved_v1.js
  static/js/vsp_datasource_tab_simple_v1.js
  static/js/vsp_settings_advanced_v1.js
  static/js/vsp_rules_editor_v1.js
)
for f in "${JS_LIST[@]}"; do
  if [ -f "$f" ]; then
    echo "-- node --check $f"
    node --check "$f" || true
  else
    echo "[MISS] $f"
  fi
done

echo
echo "== [B] Inspect suspected line ~520 =="
if [ -f static/js/vsp_runs_commercial_panel_v1.js ]; then
  nl -ba static/js/vsp_runs_commercial_panel_v1.js | sed -n '500,540p' || true
fi

echo
echo "== [C] Template script order/dup =="
TPL=templates/vsp_dashboard_2025.html
if [ -f "$TPL" ]; then
  echo "-- chart/enhance tags --"
  grep -nE "vsp_dashboard_charts|charts_pretty|vsp_dashboard_enhance" "$TPL" || true
  echo "-- duplicated script src (if any) --"
  grep -oE 'src="/static/js/[^"]+"' "$TPL" | sort | uniq -c | sort -nr | head -n 30
else
  echo "[MISS] $TPL"
fi

echo
echo "== DONE =="
