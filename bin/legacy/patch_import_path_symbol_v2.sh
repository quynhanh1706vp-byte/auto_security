#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_import_Path_symbol_${TS}"
echo "[BACKUP] $F.bak_import_Path_symbol_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Need Path symbol if code uses Path(...)
uses_path = bool(re.search(r'(?m)\bPath\s*\(', t))

# Plain import = from pathlib import Path  (NOT "as ...")
plain = bool(re.search(r'(?m)^\s*from\s+pathlib\s+import\s+Path(?!\s+as)\b', t))

if uses_path and not plain:
    # insert after initial import block (or at top)
    m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", t)
    pos = m.end(0) if m else 0
    ins = "\nfrom pathlib import Path  # VSP_IMPORT_PATH_SYMBOL_V2\n"
    t = t[:pos] + ins + t[pos:]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted plain Path import (no alias)")
else:
    print("[OK] Path symbol already available or not used")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
