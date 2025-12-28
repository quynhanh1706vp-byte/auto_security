#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

cp "$CSS" "${CSS}.bak_settings_css_unify_v4_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup security_resilient.css."

python3 - << 'PY'
from pathlib import Path

path = Path("static/css/security_resilient.css")
data = path.read_text(encoding="utf-8")

marker = "/* ========== SETTINGS PAGE FINAL UNIFY V4 ========== */"
if marker in data:
    print("[INFO] Block SETTINGS PAGE FINAL UNIFY V4 đã tồn tại, bỏ qua append.")
else:
    block = f"""

{marker}
/* Căn layout Settings giống các tab khác hơn */
.sb-main.sb-main-settings {
  padding: 32px 40px 40px;
  display: flex;
  justify-content: center;
  align-items: flex-start;
}

.sb-main.sb-main-settings .sb-settings-wrapper {
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
}

/* Tiêu đề + mô tả trên bảng */
.sb-main.sb-main-settings .sb-settings-title {
  font-size: 20px;
  font-weight: 600;
  letter-spacing: .06em;
  text-transform: uppercase;
  margin: 0 0 6px 0;
}

.sb-main.sb-main-settings .sb-settings-subtitle {
  font-size: 13px;
  opacity: .80;
  margin: 0 0 2px 0;
}

/* Đẩy bảng xuống một chút cho thoáng giống Dashboard */
.sb-main.sb-main-settings .sb-table-settings {
  margin-top: 12px;
}
"""
    path.write_text(data.rstrip() + block + "\\n", encoding="utf-8")
    print("[OK] Đã append block SETTINGS PAGE FINAL UNIFY V4 vào security_resilient.css.")
PY

echo "[DONE] patch_settings_css_unify_v4.sh hoàn thành."
