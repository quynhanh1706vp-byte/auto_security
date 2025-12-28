#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

if grep -q 'VSP_KPI_AUTO_LOADED' "$JS"; then
  echo "[INFO] Đã patch KPI autoload trước đó, bỏ qua."
  exit 0
fi

BACKUP="${JS}.bak_kpi_autoload_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

cat >> "$JS" << 'JSAPPEND'

// [VSP][KPI_AUTOLOAD] Ensure KPI dashboard JS is loaded via console patch
(function () {
  try {
    if (window.VSP_KPI_AUTO_LOADED) {
      return;
    }
    window.VSP_KPI_AUTO_LOADED = true;

    var s = document.createElement("script");
    s.src = "/static/js/vsp_dashboard_kpi_v1.js";
    s.async = true;
    s.onload = function () {
      try {
        console.log("[VSP][KPI_AUTOLOAD] vsp_dashboard_kpi_v1.js loaded via console patch");
      } catch (e) {}
    };
    s.onerror = function (e) {
      try {
        console.warn("[VSP][KPI_AUTOLOAD] Failed to load KPI script", e);
      } catch (e2) {}
    };

    if (document.head) {
      document.head.appendChild(s);
    } else {
      document.addEventListener("DOMContentLoaded", function () {
        document.head.appendChild(s);
      });
    }
  } catch (e) {
    try {
      console.error("[VSP][KPI_AUTOLOAD] Error while injecting KPI script", e);
    } catch (e2) {}
  }
})();
JSAPPEND

echo "[OK] Đã append KPI autoload vào $JS"
