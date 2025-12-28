#!/usr/bin/env bash
set -e

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TEMPLATE="$ROOT/templates/base.html"

if [ ! -f "$TEMPLATE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html – check lại PATH."
  exit 1
fi

cp "$TEMPLATE" "$TEMPLATE.bak_flask_badge_$(date +%Y%m%d_%H%M%S)"

python3 - << 'PY'
from pathlib import Path

path = Path("templates/base.html")
html = path.read_text(encoding="utf-8")

badge = """
  <div style="position:fixed; right:16px; bottom:10px; font-size:11px; color:#38fca4; opacity:0.7; z-index:9999;">
    FLASK LIVE UI
  </div>
"""

marker = "</body>"

if "FLASK LIVE UI" in html:
    print("[i] Badge đã tồn tại, không chỉnh nữa.")
else:
    if marker not in html:
        raise SystemExit("[ERR] Không tìm thấy </body> trong base.html")
    html = html.replace(marker, badge + "\n" + marker)
    path.write_text(html, encoding="utf-8")
    print("[OK] Đã chèn badge FLASK LIVE UI vào base.html.")
PY
