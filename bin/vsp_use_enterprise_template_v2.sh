#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
SRC="$ROOT/templates/vsp_5tabs_enterprise_v2.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không thấy $TPL"
  exit 1
fi

if [ ! -f "$SRC" ]; then
  echo "[ERR] Không thấy $SRC (file enterprise V2)"
  exit 1
fi

# Backup bản đang dùng
cp "$TPL" "$TPL.bak_before_enterprise_v2_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] -> $TPL.bak_before_enterprise_v2_*"

python - << 'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
src = Path("templates/vsp_5tabs_enterprise_v2.html")

tpl_txt = tpl.read_text(encoding="utf-8")
src_txt = src.read_text(encoding="utf-8")

def extract_body(html: str) -> str | None:
    m = re.search(r"<body[^>]*>(.*)</body>", html, re.I | re.S)
    return m.group(1).strip() if m else None

body_new = extract_body(src_txt)
if not body_new:
    raise SystemExit("[ERR] Không tìm thấy <body> trong vsp_5tabs_enterprise_v2.html")

def replace_body(html: str, body: str) -> str:
    def _repl(m):
        return m.group(1) + "\n" + body + "\n" + m.group(3)
    new_html, n = re.subn(
        r"(<body[^>]*>)(.*)(</body>)",
        _repl,
        html,
        flags=re.I | re.S,
    )
    if n == 0:
        raise SystemExit("[ERR] Không tìm thấy <body> trong vsp_dashboard_2025.html")
    return new_html

tpl_new = replace_body(tpl_txt, body_new)
tpl.write_text(tpl_new, encoding="utf-8")
print("[OK] Đã thay body của vsp_dashboard_2025.html bằng enterprise V2.")
PY
