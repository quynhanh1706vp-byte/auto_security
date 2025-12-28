#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_dashboard_charts_v2.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không thấy $JS"
  exit 1
fi

BACKUP="${JS}.bak_stub_v3_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

python - << 'PY'
from pathlib import Path

js = Path("static/js/vsp_dashboard_charts_v2.js")

stub = r"""
// VSP_DASHBOARD_CHARTS_V2_STUB
// Legacy charts_v2 đã được thay bằng pretty_v3.

(function () {
  console.log('[VSP_CHARTS_V2_STUB] legacy charts_v2 replaced by pretty_v3');

  function forwardToV3(dashboard) {
    if (window.VSP_DASHBOARD_CHARTS_V3 &&
        typeof window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard === 'function') {
      try {
        window.VSP_DASHBOARD_CHARTS_V3.updateFromDashboard(dashboard);
      } catch (e) {
        console.error('[VSP_CHARTS_V2_STUB] error in V3 charts', e);
      }
    } else {
      console.warn('[VSP_CHARTS_V2_STUB] V3 charts chưa sẵn, skip.');
    }
  }

  // Global API mà vsp_dashboard_enhance_v1.js dùng
  window.VSP_DASHBOARD_CHARTS = window.VSP_DASHBOARD_CHARTS || {};
  window.VSP_DASHBOARD_CHARTS.updateFromDashboard = forwardToV3;
  window.vspDashboardChartsUpdateFromDashboard = forwardToV3;
})();
"""

js.write_text(stub.strip() + "\n", encoding="utf-8")
print("[PATCH] Đã ghi stub V2 -> forward sang V3 hoàn toàn.")
PY

echo "[DONE] vsp_dashboard_charts_v2_stub_v1.sh xong."
