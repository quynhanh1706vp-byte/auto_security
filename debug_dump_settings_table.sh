#!/usr/bin/env bash
set -e
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import io

path = "app.py"
text = io.open(path, "r", encoding="utf-8").read()

marker = "<!-- SETTINGS -->"
idx = text.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy '<!-- SETTINGS -->' trong app.py.")
    raise SystemExit(1)

print("[i] Found '<!-- SETTINGS -->' at offset", idx)

table_start = text.find("<table", idx)
if table_start == -1:
    print("[ERR] Không tìm thấy <table> sau '<!-- SETTINGS -->'.")
    raise SystemExit(1)

table_end = text.find("</table>", table_start)
if table_end == -1:
    print("[ERR] Không tìm thấy </table> sau <table> SETTINGS.")
    raise SystemExit(1)

table_block = text[table_start:table_end+len("</table>")]

print("\\n===== SETTINGS TABLE BEGIN =====")
print(table_block)
print("===== SETTINGS TABLE END =====")
PY
