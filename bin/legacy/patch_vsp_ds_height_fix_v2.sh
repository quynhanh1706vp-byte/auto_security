#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy JS: $JS" >&2
  exit 1
fi

if grep -q "VSP_DS_HEIGHT_FIX_V2" "$JS"; then
  echo "[INFO] VSP_DS_HEIGHT_FIX_V2 đã tồn tại trong vsp_console_patch_v1.js – skip."
  exit 0
fi

BACKUP="$JS.bak_ds_height_v2_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

python - << 'PY'
import pathlib

js_path = pathlib.Path("static/js/vsp_console_patch_v1.js")
txt = js_path.read_text(encoding="utf-8")

snippet = r"""

// === VSP_DS_HEIGHT_FIX_V2 – stronger override for Data Source charts ===
(function() {
  if (window.VSP_DS_HEIGHT_FIX_V2) return;
  window.VSP_DS_HEIGHT_FIX_V2 = true;
  const LOG = "[VSP_DS_HEIGHT_FIX_V2]";

  function hardShrinkDsCharts() {
    const tab = document.querySelector("#vsp-tab-datasource");
    if (!tab) return;

    const canvases = tab.querySelectorAll("canvas");
    if (!canvases.length) return;

    canvases.forEach(cv => {
      try {
        // Ép height canvas
        cv.style.setProperty("height", "220px", "important");
        cv.style.setProperty("max-height", "220px", "important");
        cv.height = 220;

        // Ép container trực tiếp
        const parent = cv.parentElement;
        if (parent) {
          parent.style.setProperty("height", "230px", "important");
          parent.style.setProperty("max-height", "230px", "important");
          parent.style.overflow = "hidden";
        }

        // Ép card/wrapper lớn quanh chart
        const card = cv.closest(".vsp-card") || cv.closest(".card") || cv.closest(".panel");
        if (card) {
          card.style.setProperty("max-height", "280px", "important");
          card.style.overflow = "hidden";
        }
      } catch (e) {
        console.warn(LOG, "Error shrink chart:", e);
      }
    });

    console.log(LOG, "Hard shrink applied to", canvases.length, "canvas elements.");
  }

  // Gọi khi document sẵn sàng
  if (document.readyState === "complete" || document.readyState === "interactive") {
    hardShrinkDsCharts();
  } else {
    document.addEventListener("DOMContentLoaded", hardShrinkDsCharts);
  }

  // Observer mọi thay đổi để luôn ép lại khi Chart.js re-render
  try {
    const obs = new MutationObserver(() => hardShrinkDsCharts());
    obs.observe(document.querySelector("#vsp-tab-datasource") || document.body, {
      childList: true,
      subtree: true
    });
    console.log(LOG, "MutationObserver attached.");
  } catch (e) {
    console.warn(LOG, "Cannot attach MutationObserver:", e);
    setInterval(hardShrinkDsCharts, 1500);
  }
})();
"""

js_path.write_text(txt + snippet, encoding="utf-8")
print("[PATCH] Đã append VSP_DS_HEIGHT_FIX_V2 vào vsp_console_patch_v1.js")
PY

echo "[DONE] Patch VSP_DS_HEIGHT_FIX_V2 applied."
