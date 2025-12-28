#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
BK="${APP}.bak_import_re_v1_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Nếu đã có import re (ở top-level) thì thôi
if re.search(r"(?m)^\s*import\s+re\s*$", txt):
    print("[SKIP] import re already present.")
else:
    # chèn sau shebang/encoding nếu có, hoặc ngay đầu file
    lines = txt.splitlines(True)
    out = []
    inserted = False

    i = 0
    # giữ lại shebang + coding header
    while i < len(lines) and (lines[i].startswith("#!") or "coding" in lines[i]):
        out.append(lines[i]); i += 1

    out.append("import re\n")
    inserted = True

    out.extend(lines[i:])
    txt2 = "".join(out)
    p.write_text(txt2, encoding="utf-8")
    print("[OK] inserted: import re")

PY

python3 -m py_compile "$APP" && echo "[OK] Python compile OK"
