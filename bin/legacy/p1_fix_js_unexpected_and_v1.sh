#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_and_${TS}"
echo "[BACKUP] ${JS}.bak_fix_and_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# Fix the exact Pythonism that breaks parsing
s, n1 = re.subn(r'\bpayload\.meta\s+and\s+Array\.isArray\s*\(\s*payload\.items\s*\)',
               'payload.meta && Array.isArray(payload.items)', s)

# If any other stray " and " sneaked into that helpers block, fix common forms safely
# (Only touch lines inside the helpers block to avoid accidental changes elsewhere)
m = re.search(r'/\*\s*====================\s*VSP_P1_DASHBOARD_P1_HELPERS_DEF_V1\s*====================\s*\*/', s)
if m:
    start = m.start()
    # take a window of the first ~2600 chars after helpers marker
    win = s[start:start+2600]
    win2 = win.replace(" and Array.isArray(", " && Array.isArray(")
    win2 = win2.replace(" and payload.", " && payload.")
    win2 = win2.replace(" and (", " && (")
    if win2 != win:
        s = s[:start] + win2 + s[start+2600:]

# Safety: remove accidental "payload.meta and Array.isArray(payload.items))" variants with extra spaces
s, n2 = re.subn(r'\bmeta\s+and\s+Array\.isArray', 'meta && Array.isArray', s)

Path("static/js/vsp_dashboard_gate_story_v1.js").write_text(s, encoding="utf-8")
print("[OK] patched. replacements:", {"payload.meta and items": n1, "meta and": n2})

# Quick assert: no raw ' and ' token in the helpers block header area
head = s[:3500]
if re.search(r'\b(and)\b', head):
    print("[WARN] still found token 'and' near file head; please grep it.")
PY

echo "== node syntax check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] node --check PASS"

echo "[DONE] Fixed 'Unexpected identifier and' syntax error."
echo "Next: restart UI service then HARD refresh /vsp5 (Ctrl+Shift+R)."
