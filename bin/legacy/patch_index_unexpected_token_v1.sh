#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
T="$ROOT/templates/index.html"

# Backup trước khi sửa
cp "$T" "$T.bak_unexpected_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html")
txt = p.read_text(encoding="utf-8")

old = "      <script>\n  (function() {"
new = "</script>\n<script>\n  (function() {"

if old not in txt:
    print("[ERR] Pattern not found, không patch được.")
    raise SystemExit(1)

txt = txt.replace(old, new, 1)
p.write_text(txt, encoding="utf-8")
print("[OK] Patched index.html – đóng </script> trước Tab switcher.")
PY
