#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"
JS="$ROOT/static/run_scan_loading.js"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

########################################
# 1) Ẩn/loại bỏ các đoạn mô tả dài
########################################
python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
orig = data

# Ẩn đoạn bắt đầu bằng "Khung này dùng để nhập..."
data = re.sub(
    r"Khung này dùng để nhập[^<]*",  # chỉ xoá text, giữ lại thẻ nếu có
    "",
    data
)

# Ẩn đoạn bắt đầu bằng "Panel này chỉ dùng để ghi nhớ..."
data = re.sub(
    r"Panel này chỉ dùng để ghi nhớ[^<]*",
    "",
    data
)

if data != orig:
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã ẩn text hướng dẫn RUN panel.")
else:
    print("[INFO] Không tìm thấy text cần ẩn – có thể đã được sửa tay trước đó.")
PY

########################################
# 2) Ghi đè JS run_scan_loading.js thành stub an toàn
########################################
cat > "$JS" <<'JS'
/**
 * SB RUN PANEL – UI ONLY
 * File stub: không chạy scan thật, chỉ log ra console.
 * Dùng để tránh black screen nếu backend/CLI chưa wire xong.
 */
document.addEventListener('DOMContentLoaded', function () {
  var btn =
    document.querySelector('.sb-run-card button') ||
    document.querySelector('#sb-run-btn');

  if (!btn) {
    console.log('[SB-RUN] Không tìm thấy nút RUN trên UI (stub).');
    return;
  }

  btn.addEventListener('click', function (ev) {
    console.log('[SB-RUN] Click RUN (UI only – không chạy scan thật).');
    // Không redirect, không fetch API, không overlay – để nguyên UI.
    // Nếu sau này muốn gọi CLI/API thì sửa file này.
  });
});
JS

echo "[OK] Đã ghi stub JS cho run_scan_loading.js"

echo "[DONE] sb_run_panel_ui_only.sh hoàn thành."
