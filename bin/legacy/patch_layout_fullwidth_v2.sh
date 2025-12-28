#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

CSS="static/css/security_resilient.css"
echo "[i] CSS = $CSS"

python3 - <<'PY'
from pathlib import Path
import re

css = Path("static/css/security_resilient.css")
text = css.read_text(encoding="utf-8")

# Thử nới rộng container chính .sb-main-inner (hoặc class tương tự)
patterns = [
    (r"(\.sb-main-inner\s*\{[^}]*max-width:\s*)\d+px",  "sb-main-inner"),
    (r"(\.sb-content-inner\s*\{[^}]*max-width:\s*)\d+px", "sb-content-inner"),
]

changed = False
for pat, name in patterns:
    new = re.sub(pat, r"\1 1440px", text)
    if new != text:
        text = new
        print(f"[OK] Đã tăng max-width cho .{name} lên 1440px.")
        changed = True

if not changed:
    print("[WARN] Không tìm thấy block .sb-main-inner / .sb-content-inner để patch – bỏ qua.")

css.write_text(text, encoding="utf-8")
PY
