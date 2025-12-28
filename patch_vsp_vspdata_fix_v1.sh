#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] VSP_DATA syntax fix"

python - << 'PY'
from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")

paths = [
    ROOT / "my_flask_app/templates/vsp_5tabs_full.html",
    ROOT / "templates/index.html",
]

patterns = [
    (re.compile(r"window\\.VSP_DATA\\s*=\\s*;"), "window.VSP_DATA = {};"),
    (re.compile(r"window\\.VSP_DATA\\s*=\\s*:\\s*\\{\\s*\\};"), "window.VSP_DATA = {};"),
]

for p in paths:
    if not p.is_file():
        print(f"[SKIP] {p} không tồn tại.")
        continue

    txt = p.read_text(encoding="utf-8")
    orig = txt
    changed = False

    for pat, repl in patterns:
        new_txt, n = pat.subn(repl, txt)
        if n > 0:
            txt = new_txt
            changed = True
            print(f"[FIX] {p.name}: sửa {n} occurrence(s) window.VSP_DATA -> '{{}}'")

    if changed and txt != orig:
        backup = p.with_suffix(p.suffix + ".bak_vspdata_fix")
        backup.write_text(orig, encoding="utf-8")
        p.write_text(txt, encoding="utf-8")
        print(f"[OK] Ghi lại {p} (backup -> {backup.name})")
    else:
        print(f"[SKIP] {p} không cần sửa.")
PY

echo "[PATCH] Done."
