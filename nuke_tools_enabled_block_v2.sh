#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"
echo "[i] Tìm toàn bộ file có chứa block help 'Tools enabled...'"

FILES=$(grep -R -l \
  -e "Tools enabled" \
  -e "Mỗi dòng tương ứng với 1 tool" \
  -e "Bật/tắt tool + mode cho từng tool" \
  -e "Kết quả sẽ được lưu vào file" \
  -e "tool_config.json" \
  . 2>/dev/null || true)

if [ -z "$FILES" ]; then
  echo "[INFO] Không tìm thấy file nào chứa block help, không làm gì."
  exit 0
fi

echo "[i] Các file sẽ xử lý:"
echo "$FILES"

printf '%s\n' "$FILES" | python3 - <<'PY'
import sys, os

patterns = [
    "Tools enabled",
    "Mỗi dòng tương ứng với 1 tool",
    "Bật/tắt tool + mode cho từng tool",
    "Kết quả sẽ được lưu vào file",
    "tool_config.json",
]

def should_drop(line: str) -> bool:
    return any(p in line for p in patterns)

files = [line.strip() for line in sys.stdin if line.strip()]

for path in files:
    if not os.path.isfile(path):
        continue
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()

    out = []
    changed = False
    for line in lines:
        if should_drop(line):
            changed = True
            continue
        out.append(line)

    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
        print(f"[OK] Đã bỏ các dòng block help trong {path}")
    else:
        print(f"[INFO] {path}: không có dòng nào cần bỏ.")
PY

echo "[DONE] Đã loại bỏ toàn bộ dòng 'Tools enabled + mô tả' trong UI."
