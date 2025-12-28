#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[i] ROOT = $ROOT"
echo "[i] Sẽ tìm & bỏ toàn bộ các dòng chứa help 'Tools enabled' + mô tả VN trong toàn bộ UI..."

patterns=(
  "Tools enabled"
  "Mỗi dòng tương ứng với 1 tool"
  "Bật/tắt tool + mode cho từng tool"
  "Kết quả sẽ được lưu vào file"
  "tool_config.json"
)

# Tìm tất cả file có chứa bất kỳ pattern nào
FILES=$(grep -R -l -e "Tools enabled" \
                    -e "Mỗi dòng tương ứng với 1 tool" \
                    -e "Bật/tắt tool + mode cho từng tool" \
                    -e "Kết quả sẽ được lưu vào file" \
                    -e "tool_config.json" . 2>/dev/null || true)

if [ -z "$FILES" ]; then
  echo "[INFO] Không tìm thấy file nào chứa block help, không làm gì."
  exit 0
fi

echo "[i] Các file sẽ được xem xét:"
echo "$FILES"

# Với mỗi file: bỏ mọi dòng có chứa 1 trong các pattern trên
python3 - <<'PY'
import sys, os

root = "."
patterns = [
    "Tools enabled",
    "Mỗi dòng tương ứng với 1 tool",
    "Bật/tắt tool + mode cho từng tool",
    "Kết quả sẽ được lưu vào file",
    "tool_config.json",
]

def should_drop(line: str) -> bool:
    return any(p in line for p in patterns)

# Đọc danh sách file từ STDIN do shell cung cấp
files = sys.stdin.read().strip().splitlines()
for path in files:
    if not path:
        continue
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
PY <<< "$FILES"

echo "[DONE] Đã loại bỏ toàn bộ dòng 'Tools enabled + mô tả' trong UI."
