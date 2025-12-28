#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_import_path_${TS}"
echo "[BACKUP] $F.bak_import_path_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# If already imported, do nothing
if re.search(r'(?m)^\s*from\s+pathlib\s+import\s+Path(\s|,|$)', t) or re.search(r'(?m)^\s*import\s+pathlib\b', t):
    print("[OK] Path import already present")
else:
    # Insert after the initial import block (or at top)
    m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", t)
    pos = m.end(0) if m else 0
    ins = "\nfrom pathlib import Path  # VSP_IMPORT_PATH_V1\n"
    t = t[:pos] + ins + t[pos:]
    p.write_text(t, encoding="utf-8")
    print("[OK] inserted from pathlib import Path")

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] import Path patch applied"
