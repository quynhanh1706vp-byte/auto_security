#!/usr/bin/env bash
set -e
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
python3 - "$APP" <<'PY'
import sys, io, re

path = sys.argv[1]
text = io.open(path, "r", encoding="utf-8").read()
orig = text

# Xoá <tr> cụ thể mình đã chèn tay: STT 8 + ENABLE_CODEQL + N/A
pattern = re.compile(
    r"\s*<tr>\s*<td>8</td>.*?CodeQL\s*–\s*Multi-language\s*Code\s*Scanner.*?ENABLE_CODEQL.*?N/A.*?</tr>",
    re.DOTALL
)

new_text, n = pattern.subn("", text)
if n > 0:
    io.open(path, "w", encoding="utf-8").write(new_text)
    print(f"[OK] Đã xóa {n} hàng CodeQL HTML thô khỏi app.py.")
else:
    print("[i] Không tìm thấy hàng CodeQL HTML thô để xóa (có thể đã xóa trước đó).")
PY
