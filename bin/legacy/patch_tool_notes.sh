#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text()

if "patch_tool_notes.js" in html:
    print("[OK] Template đã có hook patch_tool_notes.js, bỏ qua.")
else:
    if "</body>" not in html:
        print("[ERR] Không tìm thấy </body> trong index.html")
    else:
        snippet = "    <script src=\"{{ url_for('static', filename='patch_tool_notes.js') }}\"></script>\\n</body>"
        html = html.replace("</body>", snippet)
        path.write_text(html)
        print("[OK] Đã chèn script patch_tool_notes.js trước </body>.")
PY

echo "[DONE] patch_tool_notes.sh hoàn thành."
