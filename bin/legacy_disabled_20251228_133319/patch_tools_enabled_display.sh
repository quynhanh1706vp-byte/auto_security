#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/index.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

cp "$TPL" "$TPL.bak_tools_enabled_$(date +%Y%m%d_%H%M%S)"

python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Đổi hiển thị Tools enabled: {{ total_tools }}/{{ enabled_tools }} -> enabled/total
pattern = r'(Tools enabled[^<]*>\s*){{\s*total_tools\s*}}\s*/\s*{{\s*enabled_tools\s*}}'
repl    = r'\1{{ enabled_tools }}/{{ total_tools }}'

new_data, n = re.subn(pattern, repl, data, count=1)
if n == 0:
    print("[WARN] Không tìm thấy block Tools enabled với total_tools/enabled_tools, không sửa gì.")
else:
    print("[OK] Đã sửa Tools enabled: dùng enabled_tools/total_tools.")

path.write_text(new_data, encoding="utf-8")
PY
