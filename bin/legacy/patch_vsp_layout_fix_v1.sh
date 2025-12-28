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

# Nếu đã chèn rồi thì thôi
if grep -q "$CSS_REL" "$TPL"; then
  echo "[INFO] CSS $CSS_REL đã được chèn trước đó – skip."
  exit 0
fi

BACKUP="$TPL.bak_layout_fix_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

export VSP_TPL="$TPL"

python - << 'PY'
import os, pathlib, re, sys

tpl = pathlib.Path(os.environ["VSP_TPL"])

try:
    txt = tpl.read_text(encoding="utf-8")
except FileNotFoundError:
    print(f"[ERR] Không đọc được file: {tpl}", file=sys.stderr)
    sys.exit(1)

link_tag = "  <link rel=\"stylesheet\" href=\"{{ url_for('static', filename='css/vsp_layout_fix_v1.css') }}\">\n\n"

m = re.search(r"\s*<style>", txt)
if not m:
    print("[ERR] Không tìm thấy <style> trong vsp_dashboard_2025.html để chèn CSS link", file=sys.stderr)
    sys.exit(1)

new_txt = txt[:m.start()] + link_tag + txt[m.start():]
tpl.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chèn link CSS layout_fix vào vsp_dashboard_2025.html")
PY

echo "[DONE] Layout fix V1 đã được apply."
