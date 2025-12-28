#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

# nếu đã chèn rồi thì thôi
if "scan_button_handler.js" in html:
    print("[OK] index.html đã load scan_button_handler.js, bỏ qua.")
else:
    # chèn trước </body>
    script_snippet = (
        '    <script src="{{ url_for(\\'static\\', '
        'filename=\\'js/scan_button_handler.js\\') }}"></script>\\n'
    )
    new_html, n = re.subn(r"</body>", script_snippet + "</body>", html, count=1, flags=re.IGNORECASE)
    if n == 0:
        print("[ERR] Không tìm thấy </body> để chèn script.")
    else:
        path.write_text(new_html, encoding="utf-8")
        print("[OK] Đã chèn scan_button_handler.js trước </body>.")
PY
