#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [A] JS parse check (node --check) =="
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
  [ -f "$f" ] || { echo "[MISS] $f"; continue; }
  echo "-- node --check $f"
  node --check "$f"
done

echo
echo "== [B] Charts engine exported? =="
node - <<'NODE'
const fs = require("fs");
const t = fs.readFileSync("static/js/vsp_dashboard_charts_pretty_v3.js","utf8");
console.log("has VSP_CHARTS_ENGINE_V3 =", /VSP_CHARTS_ENGINE_V3/.test(t));
console.log("has initAll =", /initAll\s*:/.test(t));
NODE

echo
echo "== [C] Canvas IDs expected by pretty_v3 (grep getElementById) =="
grep -nE "getElementById\\(|querySelector\\('#" static/js/vsp_dashboard_charts_pretty_v3.js | head -n 200 || true

echo
echo "== [D] Does template include those canvas? (quick scan) =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[MISS] $TPL"; exit 0; }
grep -nE "<canvas|vsp-chart|chart-" "$TPL" | head -n 200 || true

echo
echo "== [E] Template script order (charts/enhance) =="
grep -nE "vsp_dashboard_enhance|vsp_dashboard_charts_v2|vsp_dashboard_charts_pretty_v3" "$TPL" || true

echo
echo "[OK] DONE"
