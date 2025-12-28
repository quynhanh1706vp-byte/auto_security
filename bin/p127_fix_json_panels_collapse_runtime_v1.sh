#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p127_${TS}"
echo "[OK] backup: ${F}.bak_p127_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# 1) Fix startswith/endswith -> startsWith/endsWith (runtime bug)
s = s.replace(".startswith(", ".startsWith(").replace(".endswith(", ".endsWith(")
s = s.replace(".startswith", ".startsWith").replace(".endswith", ".endsWith")

# 2) On /c/settings and /c/rule_overrides: collapse even smaller JSON blocks (minLines=8)
# Patch only once
if "VSP_P127_MINLINES" not in s:
    pat = r'(\n\s*const\s+lines\s*=\s*txt\.split\("\\n"\)\.length\s*\n\s*)if\s*\(\s*!looksJson\s*\|\|\s*lines\s*<\s*30\s*\)\s*continue;'
    m = re.search(pat, s)
    if m:
        repl = (
            m.group(1)
            + 'const VSP_P127_MINLINES = (/(?:^|\\/)c\\/(settings|rule_overrides)(?:$|\\b)/.test((location.pathname||"")));'
            + '\n        const minLines = VSP_P127_MINLINES ? 8 : 30;'
            + '\n        if (!looksJson || lines < minLines) continue;'
        )
        s = re.sub(pat, repl, s, count=1)

# 3) Make sure details is collapsed by default (defensive)
if "details.open = false" not in s:
    # not forcing; leave if already there
    pass

if s == orig:
    print("[OK] no changes needed (already fixed)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched vsp_c_common_v1.js (p127)")

# Quick sanity: show the key line if present
idx = s.find("looksJson")
if idx != -1:
    frag = s[max(0, idx-220): idx+240]
    print("---- snippet ----")
    print(frag)
    print("---- /snippet ----")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skipped node --check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
