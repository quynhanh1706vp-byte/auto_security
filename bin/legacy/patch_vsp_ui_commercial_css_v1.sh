#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

CSS_LINE="{{ url_for('static', filename='css/vsp_ui_commercial_v1.css') }}"

# Nếu đã có link rồi thì thôi
if grep -q "vsp_ui_commercial_v1.css" "$TPL"; then
  echo "[INFO] vsp_ui_commercial_v1.css đã được include – skip."
  exit 0
fi

BACKUP="$TPL.bak_ui_commercial_css_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
import pathlib, re, sys

tpl = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8")

m = re.search(r"</head>", txt, re.IGNORECASE)
if not m:
    print("[ERR] Không tìm thấy </head> trong vsp_dashboard_2025.html", file=sys.stderr)
    sys.exit(1)

link_tag = '  <link rel="stylesheet" href="{{ url_for(\\'static\\', filename=\\'css/vsp_ui_commercial_v1.css\\') }}">\\n'

new_txt = txt[:m.start()] + link_tag + txt[m.start():]
tpl.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chèn link CSS thương mại vào vsp_dashboard_2025.html")
PY

echo "[DONE] patch_vsp_ui_commercial_css_v1.sh hoàn tất."
