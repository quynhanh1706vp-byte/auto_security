#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy JS: $JS" >&2
  exit 1
fi

if grep -q "VSP_DS_HEIGHT_FIX_V1" "$JS"; then
  echo "[INFO] VSP_DS_HEIGHT_FIX_V1 đã tồn tại trong vsp_console_patch_v1.js – skip."
  exit 0
fi

BACKUP="$JS.bak_ds_height_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

python - << 'PY'
import pathlib

js_path = pathlib.Path("static/js/vsp_console_patch_v1.js")
txt = js_path.read_text(encoding="utf-8")

snippet = r"""

// === VSP_DS_HEIGHT_FIX_V1 – limit Data Source charts height ===
(function() {
  if (window.VSP_DS_HEIGHT_FIX_V1) return;
  window.VSP_DS_HEIGHT_FIX_V1 = true;
  const LOG = "[VSP_DS_HEIGHT_FIX]";

  function shrinkDsCharts() {
    try {
      const tab = document.querySelector("#vsp-tab-datasource");
      if (!tab) return;
      const canvases = tab.querySelectorAll("canvas");
      if (!canvases.length) return;
      canvases.forEach(cv => {
        cv.style.height = "260px";
        cv.style.maxHeight = "260px";
      });
      console.log(LOG, "Applied height=260px to", canvases.length, "canvas elements.");
    } catch (e) {
      console.warn(LOG, "Error while shrinking charts:", e);
    }
  }

  // Gọi 1 lần khi load
  if (document.readyState === "complete" || document.readyState === "interactive") {
    shrinkDsCharts();
  } else {
    document.addEventListener("DOMContentLoaded", shrinkDsCharts);
  }

  // Dùng MutationObserver để bắt mọi lần Data Source render lại chart
  try {
    const obs = new MutationObserver(() => shrinkDsCharts());
    obs.observe(document.documentElement, { childList: true, subtree: true });
    console.log(LOG, "MutationObserver attached.");
  } catch (e) {
    console.warn(LOG, "Cannot attach MutationObserver:", e);
    // fallback: thỉnh thoảng thu nhỏ lại
    setInterval(shrinkDsCharts, 1500);
  }
})();
"""

js_path.write_text(txt + snippet, encoding="utf-8")
print("[PATCH] Đã append VSP_DS_HEIGHT_FIX_V1 vào vsp_console_patch_v1.js")
PY

echo "[DONE] Patch VSP_DS_HEIGHT_FIX_V1 applied."
