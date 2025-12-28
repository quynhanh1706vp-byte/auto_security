#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, os

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
orig = text

# 1) XÓA PHẦN TỬ CHỨA CÂU HELP "Mỗi dòng tương ứng với 1 tool..."
needle = "Mỗi dòng tương ứng với 1 tool"
while needle in text:
    idx = text.find(needle)
    # lùi trái tới dấu '<' gần nhất (đầu tag)
    start = text.rfind("<", 0, idx)
    # tiến phải tới '</' kế tiếp rồi tới '>' (cuối tag đóng)
    end_tag = text.find("</", idx)
    if end_tag == -1:
        # fallback: cắt tới hết dòng
        end = text.find("\n", idx)
        if end == -1:
            end = len(text)
    else:
        end_gt = text.find(">", end_tag)
        if end_gt == -1:
            end = end_tag
        else:
            end = end_gt + 1

    if start == -1:
        # không tìm được '<', chỉ xóa đoạn text thôi
        start = idx

    print(f"[OK] Xóa block help từ {start} đến {end} trong templates/index.html")
    text = text[:start] + text[end:]

# 2) XÓA CHUỖI " 8/7" (có khoảng trắng phía trước) TRONG TEMPLATE
if " 8/7" in text:
    text = text.replace(" 8/7", " ")
    print("[OK] Đã xóa mọi chuỗi ' 8/7' trong templates/index.html")

if text != orig:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("[DONE] templates/index.html đã được cập nhật.")
else:
    print("[INFO] Không có gì thay đổi trong templates/index.html (có thể đã sạch).")
PY
