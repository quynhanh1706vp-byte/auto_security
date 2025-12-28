#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drill_art_colon_${TS}"
echo "[BACKUP] $F.bak_drill_art_colon_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK = 'DRILL_ART_V2] installed'
i = None
for idx, ln in enumerate(lines):
    if MARK in ln:
        i = idx
        break

if i is None:
    print("[ERR] cannot find marker:", MARK)
    raise SystemExit(3)

# find the first close-line after marker that looks like IIFE close: contains ")()"
j = None
for k in range(i+1, min(i+25, len(lines))):
    if ")()" in lines[k] or ")();" in lines[k] or "})();" in lines[k]:
        j = k
        break

if j is None:
    # fallback: look for line with ")(" then ")"
    for k in range(i+1, min(i+25, len(lines))):
        if re.search(r"\)\s*\(\s*\)\s*;?", lines[k]):
            j = k
            break

if j is None:
    print("[ERR] cannot find IIFE close line after marker")
    raise SystemExit(4)

old = lines[j].rstrip("\n")
ln = lines[j]

# normalize: keep everything up to the FIRST ';' (inclusive). If no ';' but has ")()": keep to end + ';'
if ";" in ln:
    cut = ln.split(";", 1)[0] + ";\n"
else:
    cut = ln.rstrip("\n").rstrip() + ";\n"

# also strip any trailing junk after ");" if present
m = re.search(r"(.*\)\s*;\s*)", cut)
if m:
    cut = m.group(1).rstrip() + "\n"

lines[j] = cut

p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched close-line")
print("[AT] line", j+1)
print("[OLD]", old)
print("[NEW]", lines[j].rstrip("\n"))
PY

echo "== node --check bundle =="
node --check "$F"

echo "== grep context =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace").splitlines()
for i,ln in enumerate(s):
    if 'DRILL_ART_V2] installed' in ln:
        st=max(0,i-4); en=min(len(s),i+8)
        for k in range(st,en):
            print(f"{k+1:5d}  {s[k]}")
        break
PY

echo "== restart 8910 hardreset =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R (hard refresh) on browser"
