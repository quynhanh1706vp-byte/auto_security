#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

echo "[i] Thêm UI LITE MODE (giảm shadow/gradient/animation) vào $CSS"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [sb_lite_mode_v1] */"
if marker in css:
    print("[i] Đã có sb_lite_mode_v1, bỏ qua.")
else:
    extra = """
/* [sb_lite_mode_v1] – giao diện nhẹ cho trình duyệt yếu / mobile */
/* Nền đơn giản hơn */
body {
  background: #050809 !important;
}

/* Card phẳng, bỏ bớt shadow */
.sb-card,
.card {
  box-shadow: none !important;
  border-color: rgba(124,252,0,0.25) !important;
  background: rgba(5, 12, 8, 0.96) !important;
}

/* KPI phẳng hơn */
.kpi-card,
.kpi,
.sb-kpi-card {
  box-shadow: none !important;
  background: rgba(8, 18, 10, 0.96) !important;
}

/* Nút giữ màu nhưng bỏ hiệu ứng phức tạp */
button,
.btn,
.sb-btn,
.sb-btn-primary,
.run-btn,
.run-button {
  transition: none !important;
}

/* Bỏ animation/transitions chung để giảm repaint */
* {
  transition: none !important;
  animation: none !important;
}

/* Trên màn nhỏ (điện thoại), ưu tiên đơn giản – ẩn bớt phần nặng nếu có class đúng */
@media (max-width: 768px) {
  /* nếu các section có class dạng này thì sẽ ẩn bớt */
  .sb-section-last-runs,
  .sb-section-all-findings {
    display: none !important;
  }
}
"""
    css = css.rstrip() + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã thêm sb_lite_mode_v1 vào", path)
PY

echo "[DONE] patch_ui_lite_mode.sh hoàn thành."
