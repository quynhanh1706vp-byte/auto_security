#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_path_${TS}"
echo "[BACKUP] $F.bak_fix_path_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_FIX_RUNV1_PATH_SHADOW_V1"
if MARK in txt:
    print("[OK] already fixed:", MARK)
    raise SystemExit(0)

# 1) Ensure module-level import exists
if not re.search(r'^\s*from\s+pathlib\s+import\s+Path\s*$', txt, flags=re.M):
    # insert after last top import block line
    lines = txt.splitlines(True)
    ins = 0
    for i, ln in enumerate(lines[:200]):
        if re.match(r'^\s*(import|from)\s+\w+', ln):
            ins = i + 1
    lines.insert(ins, "from pathlib import Path  # " + MARK + "\n")
    txt = "".join(lines)
else:
    # still add marker comment somewhere safe (top) later
    pass

# 2) Remove any inner "from pathlib import Path" inside run_v1()
m = re.search(r'(?ms)^\s*def\s+run_v1\s*\(\s*\)\s*:\s*\n', txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_v1():")

start = m.start()
# find end of function by next top-level def (col 0)
m2 = re.search(r'(?m)^\s*def\s+\w+\s*\(', txt[m.end():])
if m2:
    end = m.end() + m2.start()
else:
    end = len(txt)

head = txt[:start]
body = txt[start:end]
tail = txt[end:]

# remove inner import Path lines in body
body2, n = re.subn(r'(?m)^\s*from\s+pathlib\s+import\s+Path\s*(#.*)?\n', '', body)
# also avoid accidental "Path =" assignments inside run_v1
body2, n2 = re.subn(r'(?m)^(\s*)Path(\s*)=', r'\1Path_\2=', body2)

# add marker comment near def line
if MARK not in body2:
    body2 = re.sub(r'(?m)^(def\s+run_v1\s*\(\s*\)\s*:)\s*$', r'\1  # ' + MARK, body2, count=1)

txt2 = head + body2 + tail
p.write_text(txt2, encoding="utf-8")
print(f"[OK] patched: {MARK} removed_inner_imports={n} renamed_Path_assigns={n2}")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
