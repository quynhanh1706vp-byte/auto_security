#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

python - << 'PY'
from pathlib import Path
import re

files = [
    Path("templates/vsp_dashboard_2025.html"),
    Path("templates/index.html"),
    Path("templates/vsp_index.html"),
]

pattern = re.compile(r'(<button[^>]*)(>\\s*Save settings\\s*</button>)', re.IGNORECASE)

for p in files:
    if not p.is_file():
        continue
    txt = p.read_text(encoding="utf-8")
    if "Save settings" not in txt:
        continue
    if "vsp-settings-save-btn" in txt:
        print("[INFO]", p, "đã có id vsp-settings-save-btn.")
        continue
    new_txt, n = pattern.subn(r'\\1 id="vsp-settings-save-btn"\\2', txt, count=1)
    if n:
        p.write_text(new_txt, encoding="utf-8")
        print("[OK]", p, "-> thêm id vsp-settings-save-btn cho nút Save settings.")
    else:
        print("[WARN]", p, "không match được pattern button Save settings.")
PY

echo "[PATCH] DONE. Reload browser (Ctrl+Shift+R)."
