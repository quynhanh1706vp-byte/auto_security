#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_repair_ciQ_${TS}"
echo "[BACKUP] $F.bak_repair_ciQ_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

bad = '(__ciQ||\\"\\").replace(/^\\\\?/, \\"&\\")'
good = 'String(__ciQ||"").replace(/^\\?/, "&")'

n0 = t.count(bad)
t2 = t.replace(bad, good)

# Also handle the exact form shown in your error (may appear without double escaping in file text)
bad2 = '(__ciQ||"\\"").replace(/^\\\\?/, "\\"&\\"")'
t2 = t2.replace(bad2, good)

# And the literal form visible in the file now (most likely)
bad3 = '(__ciQ||\\"\\").replace(/^\\?/, \\"&\\")'
t2 = t2.replace(bad3, good)

# If somehow the patch inserted \" directly (as in your snippet), fix that too:
bad4 = '(__ciQ||\\"\\").replace(/^\\?/, \\"&\\")'
t2 = t2.replace(bad4, good)

# Finally, fix the exact substring currently in your file (from the node error):
bad5 = '(__ciQ||\\"\\").replace(/^\\\\?/, \\"&\\")'
t2 = t2.replace(bad5, good)

# Also fix the exact raw string that appeared in your terminal output:
bad6 = '(__ciQ||\\"\\").replace(/^\\\\?/, \\"&\\")'
t2 = t2.replace(bad6, good)

# Most important: replace the exact visible broken token pattern \" inside that expression
t2 = t2.replace('(__ciQ||\\"\\")', '(__ciQ||"")').replace('\\"&\\"', '"&"')

if t2 == t:
    print("[WARN] no bad pattern replaced (file may differ) — applying targeted regex-like fallback")
    # fallback: replace any occurrences of (__ciQ||\"\") with (__ciQ||"") and \"&\" with "&"
    t2 = t2.replace('(__ciQ||\\"\\")', '(__ciQ||"")')
    t2 = t2.replace('\\"&\\"', '"&"')
    # and normalize regex literal from /^\\?/ to /^\?/
    t2 = t2.replace('/^\\\\?/', '/^\\?/')

p.write_text(t2, encoding="utf-8")
print("[OK] repaired ciQ expression tokens")
PY

node --check static/js/vsp_ui_4tabs_commercial_v1.js >/dev/null
echo "[OK] node --check OK"

echo "[DONE] repaired export HEAD URL builder. Now hard refresh Ctrl+Shift+R."
