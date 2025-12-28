#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_path_force_${TS}"
echo "[BACKUP] $F.bak_fix_path_force_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

# Ensure module-level import exists (top area)
if not re.search(r'^\s*from\s+pathlib\s+import\s+Path\s*$', txt, flags=re.M):
    # insert after import block
    lines = txt.splitlines(True)
    ins = 0
    for i, ln in enumerate(lines[:250]):
        if re.match(r'^\s*(import|from)\s+\w+', ln):
            ins = i + 1
    lines.insert(ins, "from pathlib import Path\n")
    txt = "".join(lines)

# locate run_v1 block
m = re.search(r'(?ms)^\s*def\s+run_v1\s*\(\s*\)\s*:\s*\n', txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_v1()")

start = m.start()
m2 = re.search(r'(?m)^\s*def\s+\w+\s*\(', txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)

head, body, tail = txt[:start], txt[start:end], txt[end:]

# remove any inner import Path inside run_v1
body, n = re.subn(r'(?m)^\s*from\s+pathlib\s+import\s+Path\s*(#.*)?\n', '', body)

# also prevent accidental local assignment to Path
body, n2 = re.subn(r'(?m)^(\s*)Path(\s*)=', r'\1Path_\2=', body)

p.write_text(head + body + tail, encoding="utf-8")
print("[OK] removed_inner_imports=", n, "renamed_Path_assigns=", n2)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
