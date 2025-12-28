#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] BASE = $BASE"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html"
  exit 1
fi

python3 - "$BASE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text()

marker = "<!-- PATCH_HIDE_DEBUG_JSON_V3 -->"
if marker not in html:
    print("[WARN] Không thấy marker PATCH_HIDE_DEBUG_JSON_V3 – không cần revert.")
else:
    start = html.index(marker)
    script_open = html.find("<script>", start)
    script_close = html.find("</script>", script_open)
    if script_open == -1 or script_close == -1:
        # không tìm thấy script, xóa marker thôi
        new_html = html.replace(marker, "")
        print("[WARN] Chỉ xóa marker, không thấy <script> sau đó.")
    else:
        new_html = html[:start] + html[script_close + len("</script>"):]
        print("[OK] Đã gỡ block PATCH_HIDE_DEBUG_JSON_V3 (marker + script).")

    path.write_text(new_html)
PY

echo "[DONE] revert_hide_debug_json_v3.sh hoàn thành."
