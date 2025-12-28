#!/usr/bin/env bash
set -e
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, io

path = sys.argv[1]
text = io.open(path, "r", encoding="utf-8").read()
orig = text

# Các pattern có thể có (có/không khoảng trắng, dùng ' hoặc ")
patterns = [
    "{{ tool_status['CODEQL'] }}",
    '{{ tool_status["CODEQL"] }}',
    "{{tool_status['CODEQL']}}",
    '{{tool_status["CODEQL"]}}'
]

for p in patterns:
    if p in text:
        text = text.replace(p, "N/A")

if text != orig:
    io.open(path, "w", encoding="utf-8").write(text)
    print("[OK] Đã thay mọi tool_status['CODEQL'] thành 'N/A' trong app.py.")
else:
    print("[i] Không tìm thấy tool_status['CODEQL'] trong app.py (hoặc đã thay trước đó).")
PY
