#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

marker = "SRC FOLDER"
pos = data.find(marker)
if pos == -1:
    print("[WARN] Không tìm thấy text 'SRC FOLDER' trong template.", file=sys.stderr)
    sys.exit(0)

# Tìm thẻ <input> đầu tiên sau chữ "SRC FOLDER"
m = re.search(r"<input([^>]*)>", data[pos:], flags=re.IGNORECASE)
if not m:
    print("[WARN] Không tìm thấy <input> sau 'SRC FOLDER'.", file=sys.stderr)
    sys.exit(0)

start = pos + m.start()
end   = pos + m.end()
attrs = m.group(1)

# Xử lý id
if 'id=' in attrs:
    attrs = re.sub(r'id\s*=\s*"[^\"]*"', 'id="src-folder"', attrs)
else:
    attrs += ' id="src-folder"'

# Xử lý name
if 'name=' in attrs:
    attrs = re.sub(r'name\s*=\s*"[^\"]*"', 'name="src_folder"', attrs)
else:
    attrs += ' name="src_folder"'

new_input = f"<input{attrs}>"
data = data[:start] + new_input + data[end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã gán id=\"src-folder\" name=\"src_folder\" cho ô SRC FOLDER.")
PY

echo "[DONE] patch_src_folder_input.sh hoàn thành."
