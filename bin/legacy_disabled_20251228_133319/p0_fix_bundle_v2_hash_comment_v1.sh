#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_hash_${TS}"
echo "[BACKUP] ${JS}.bak_fix_hash_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Convert illegal "# ..." comment lines (except a possible first-line hashbang "#!")
lines = s.splitlines(True)
out = []
changed = 0
for i, ln in enumerate(lines):
    # keep first-line hashbang if exists (#!/usr/bin/env node)
    if i == 0 and ln.startswith("#!"):
        out.append(ln); continue
    m = re.match(r'^([ \t]*)#(.*)\n?$', ln)
    if m:
        # turn into JS line comment
        out.append(f"{m.group(1)}//{m.group(2)}\n" if not ln.endswith("\n") else f"{m.group(1)}//{m.group(2)}")
        changed += 1
    else:
        out.append(ln)

p.write_text("".join(out), encoding="utf-8")
print("[OK] converted '#' comment lines => '//' :", changed)
PY

echo "== node --check (must be OK) =="
node --check "$JS" && echo "[OK] node --check passed: $JS"

echo
echo "NEXT: Ctrl+F5 /vsp5"
