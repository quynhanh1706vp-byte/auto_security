#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
CSS_REL="css/vsp_layout_fix_v1.css"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

# Nếu đã có link sau </style> rồi thì thôi
if grep -q "AFTER_STYLE_LAYOUT_FIX" "$TPL"; then
  echo "[INFO] Link CSS sau </style> đã tồn tại – skip."
  exit 0
fi

BACKUP="$TPL.bak_layout_fix_after_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
import pathlib, re, sys

tpl = pathlib.Path(r"templates/vsp_dashboard_2025.html")

txt = tpl.read_text(encoding="utf-8")

m = re.search(r"</style>", txt, re.IGNORECASE)
if not m:
    print("[ERR] Không tìm thấy </style> để chèn link CSS sau đó", file=sys.stderr)
    sys.exit(1)

insert = "</style>\n  <!-- AFTER_STYLE_LAYOUT_FIX -->\n  <link rel=\"stylesheet\" href=\"{{ url_for('static', filename='css/vsp_layout_fix_v1.css') }}\">\n"

new_txt = txt[:m.start()] + insert + txt[m.end():]

tpl.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chèn link CSS layout_fix sau </style> trong vsp_dashboard_2025.html")
PY

echo "[DONE] Layout fix V1b đã được apply."
