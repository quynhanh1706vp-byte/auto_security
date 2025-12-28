#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH_DS_PREVIEW] Bắt đầu patch Data Source mini-charts (preview mode)..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS_FILE="$UI_ROOT/static/js/vsp_datasource_charts_v1.js"

if [ ! -f "$JS_FILE" ]; then
  echo "[PATCH_DS_PREVIEW][WARN] Không tìm thấy JS: $JS_FILE"
  echo "[PATCH_DS_PREVIEW][WARN] Bỏ qua (có thể bản UI của bạn dùng file khác)."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${JS_FILE}.bak_preview_${TS}"
cp "$JS_FILE" "$BACKUP"
echo "[BACKUP] $JS_FILE -> $BACKUP"

export JS_FILE

python - << 'PY'
import os, pathlib, sys

js_path = pathlib.Path(os.environ["JS_FILE"])
txt = js_path.read_text(encoding="utf-8")

marker = "VSP_DS_CHARTS_PREVIEW_V1"
if marker in txt:
    print("[PATCH_DS_PREVIEW] Preview snippet đã tồn tại, bỏ qua.")
    sys.exit(0)

snippet = """

// VSP_DS_CHARTS_PREVIEW_V1
// Mini charts Data Source đang ở chế độ Preview cho V1.
// Thay vì vẽ Chart.js, hiển thị một note giải thích cho khách hàng.
(function() {
  try {
    console.log("[VSP_DS_CHARTS] Preview mode – mini charts disabled in V1.");
    var el = document.getElementById("vsp-datasource-mini-charts");
    if (!el) {
      el = document.querySelector("[data-vsp-ds-mini-charts]");
    }
    if (el && !el.dataset.vspPreviewInjected) {
      el.dataset.vspPreviewInjected = "1";
      el.innerHTML = '<div class="vsp-preview-note"><strong>Preview mini-charts</strong> – Mini charts (Severity by tool / Top directories) sẽ được bật dần từ <b>V1.5</b>. Bảng unified findings phía trên đang dùng dữ liệu thật từ tất cả tools đã scan.</div>';
    } else if (!el) {
      console.warn("[VSP_DS_CHARTS] Không tìm thấy container mini-charts (id=vsp-datasource-mini-charts hoặc [data-vsp-ds-mini-charts]).");
    }
  } catch (e) {
    console.warn("[VSP_DS_CHARTS] Preview inject error:", e);
  }
})();
"""

js_path.write_text(txt + snippet, encoding="utf-8")
print("[PATCH_DS_PREVIEW] Đã append preview snippet vào", js_path)
PY

echo "[PATCH_DS_PREVIEW] Done."
