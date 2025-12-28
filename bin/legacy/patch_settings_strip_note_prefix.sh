#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL_DIR="$ROOT/templates"

echo "[i] ROOT    = $ROOT"
echo "[i] TPL_DIR = $TPL_DIR"

if [ ! -d "$TPL_DIR" ]; then
  echo "[ERR] Không tìm thấy thư mục templates/"
  exit 1
fi

python3 - "$TPL_DIR" <<'PY'
import sys, pathlib, re

tpl_dir = pathlib.Path(sys.argv[1])
html_files = list(tpl_dir.rglob("*.html"))

if not html_files:
    print("[ERR] Không tìm thấy file .html nào trong templates/")
    raise SystemExit(1)

pattern = re.compile(r"Hoạt động bình thường\s*[-–]\s*[^:]*:\s*", re.UNICODE)

total_files = 0
total_repl  = 0

for p in html_files:
    text = p.read_text()
    if "Hoạt động bình thường" not in text:
        continue
    new_text, n = pattern.subn("", text)
    if n > 0:
        p.write_text(new_text)
        total_files += 1
        total_repl  += n
        print(f"[OK] {p}: đã bỏ prefix 'Hoạt động bình thường – ...:' ({n} lần).")

if total_files == 0:
    print("[WARN] Không tìm thấy đoạn 'Hoạt động bình thường – ...:' trong bất kỳ template nào.")
else:
    print(f"[DONE] Đã patch {total_files} file, tổng {total_repl} lần thay thế.")
PY

echo "[DONE] patch_settings_strip_note_prefix.sh hoàn thành."
