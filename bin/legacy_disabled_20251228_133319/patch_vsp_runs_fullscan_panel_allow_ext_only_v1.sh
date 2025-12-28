#!/usr/bin/env bash
set -euo pipefail

# Patch: cho phép run chỉ Source root, chỉ URL, hoặc cả 2.
# Thay block:
#   if (!targetUrl) { alert('Vui lòng nhập Target URL.'); return; }
# bằng:
#   nếu cả sourceRoot lẫn targetUrl đều rỗng -> báo lỗi
#   còn lại thì cho chạy (BE tự quyết định mode).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_runs_fullscan_panel_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy file JS panel: $FILE" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${FILE}.bak_extonly_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup file gốc thành: $BACKUP"

FILE="$FILE" python - << 'PY'
import os, pathlib, re, sys

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

pattern = r"""if\s*\(\s*!targetUrl\s*\)\s*{\s*alert\(['"]Vui lòng nhập Target URL['"]\);\s*return;\s*}"""

new_block = """if (!sourceRoot && !targetUrl) {
      alert('Vui lòng nhập ít nhất Source root hoặc Target URL.');
      return;
    }"""

regex = re.compile(pattern, re.MULTILINE)
new_txt, n = regex.subn(new_block, txt, count=1)

if n == 0:
    print("[ERR] Không tìm thấy block if (!targetUrl) ... để patch.", file=sys.stderr)
    sys.exit(1)

path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã patch vsp_runs_fullscan_panel_v1.js – cho phép run chỉ thư mục hoặc chỉ URL.")
PY
