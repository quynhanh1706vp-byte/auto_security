#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH_DASH_PREVIEW] Bắt đầu patch Dashboard (preview labels + CSS)..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TPL}.bak_preview_${TS}"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

export TPL

python - << 'PY'
import os, pathlib, sys

tpl_path = pathlib.Path(os.environ["TPL"])
txt = tpl_path.read_text(encoding="utf-8")
lower_txt = txt.lower()

changed = False

# 1) Thêm link CSS vsp_charts_2025.css vào <head> nếu chưa có
if "vsp_charts_2025.css" not in txt:
    head_pos = lower_txt.find("</head>")
    if head_pos != -1:
        link = '  <link rel="stylesheet" href="/static/css/vsp_charts_2025.css">\n'
        txt = txt[:head_pos] + link + txt[head_pos:]
        lower_txt = txt.lower()
        print("[PATCH_DASH_PREVIEW] Đã inject <link> vsp_charts_2025.css vào <head>.")
        changed = True
    else:
        print("[PATCH_DASH_PREVIEW][WARN] Không tìm thấy </head>, bỏ qua inject CSS link.")

# 2) Thêm note preview trước </body> nếu chưa có
marker = "VSP_PREVIEW_NOTE_V1"
if marker in txt:
    print("[PATCH_DASH_PREVIEW] Preview note đã tồn tại, bỏ qua.")
else:
    insert_block = """
  <!-- VSP_PREVIEW_NOTE_V1 -->
  <div class="vsp-preview-note">
    <strong>Preview analytics</strong> – Một số khối phân tích nâng cao
    (Top risk findings, noisy paths, compliance, diff, mini charts) hiện đang ở chế độ
    <b>Preview</b> và sẽ được bật dần từ <b>V1.5</b>. Các KPI và bảng dữ liệu phía trên
    đang sử dụng dữ liệu thật từ các đợt scan đã chạy.
  </div>
"""
    body_pos = lower_txt.rfind("</body>")
    if body_pos == -1:
        print("[PATCH_DASH_PREVIEW][ERR] Không tìm thấy </body> trong template, không thể chèn preview note.")
        sys.exit(1)
    txt = txt[:body_pos] + insert_block + txt[body_pos:]
    print("[PATCH_DASH_PREVIEW] Đã chèn preview note trước </body>.")
    changed = True

if changed:
    tpl_path.write_text(txt, encoding="utf-8")
    print("[PATCH_DASH_PREVIEW] ĐÃ GHI file template mới:", tpl_path)
else:
    print("[PATCH_DASH_PREVIEW] Không có thay đổi nào được áp dụng.")
PY

echo "[PATCH_DASH_PREVIEW] Done."
