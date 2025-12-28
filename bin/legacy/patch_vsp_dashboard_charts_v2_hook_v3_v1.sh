#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_dashboard_charts_v2.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không thấy $JS"
  exit 1
fi

BACKUP="${JS}.bak_hook_v3_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

python - << 'PY'
from pathlib import Path

js = Path("static/js/vsp_dashboard_charts_v2.js")
txt = js.read_text(encoding="utf-8")

hook = r"""
/* === VSP_CHARTS_V2_HOOK_V3 === */
;(function () {
  if (window.VSP_CHARTS_V2_HOOK_V3) return;
  window.VSP_CHARTS_V2_HOOK_V3 = true;
  console.log('[VSP_CHARTS_V2_HOOK_V3] override updateFromDashboard -> V3');

  function forwardToV3(dashboard) {
    if (window.VSP_DASHBOARD_CHARTS_V3 &&
        typeof window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard === 'function') {
      try {
        window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard(dashboard);
      } catch (e) {
        console.error('[VSP_CHARTS_V2_HOOK_V3] error in V3 charts', e);
      }
    } else {
      console.warn('[VSP_CHARTS_V2_HOOK_V3] V3 charts chưa sẵn, skip.');
    }
  }

  // ép global dùng forwardToV3
  window.VSP_DASHBOARD_CHARTS = window.VSP_DASHBOARD_CHARTS || {};
  window.VSP_DASHBOARD_CHARTS.updateFromDashboard = forwardToV3;
  window.vspDashboardChartsUpdateFromDashboard = forwardToV3;
})();
"""

if "VSP_CHARTS_V2_HOOK_V3" in txt:
    print("[PATCH] Hook đã tồn tại, bỏ qua.")
else:
    txt = txt + hook
    js.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã append hook V3 vào vsp_dashboard_charts_v2.js")
PY

echo "[DONE] patch_vsp_dashboard_charts_v2_hook_v3_v1.sh xong."
