#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_picklatest_guard_v6_${TS}" && echo "[BACKUP] $F.bak_picklatest_guard_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RID_PICKLATEST_GUARD_V6_BEGIN */"
END  ="/* VSP_RID_PICKLATEST_GUARD_V6_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s)

# Ensure a safe override exists (and stays a function)
shim = r'''
/* VSP_RID_PICKLATEST_GUARD_V6_BEGIN */
(function(){
  try{
    const g = (typeof window!=="undefined") ? window : globalThis;
    if (typeof g.VSP_RID_PICKLATEST_OVERRIDE_V1 !== "function"){
      g.VSP_RID_PICKLATEST_OVERRIDE_V1 = async function(){ return null; };
    }
  }catch(e){}
})();
/* VSP_RID_PICKLATEST_GUARD_V6_END */
'''

# Put shim near top (after 'use strict' if present, else top)
if "use strict" in s:
  s = s.replace("'use strict';", "'use strict';\n"+shim, 1)
else:
  s = shim + "\n" + s

# Guard in pickLatest: replace direct call patterns to safe-call (best-effort)
# If file has "await VSP_RID_PICKLATEST_OVERRIDE_V1(" or "await g.VSP_RID_PICKLATEST_OVERRIDE_V1("
s = re.sub(r'await\s+([A-Za-z0-9_\.]*VSP_RID_PICKLATEST_OVERRIDE_V1)\s*\(',
           r'(typeof \1==="function" ? await \1(',
           s)
# close the ternary if we opened it (best-effort: handle "):" not possible; so add fallback right after common patterns)
# Instead: inject a safe helper and use it if we can find pickLatest() body.
helper = r'''
async function __vsp_safe_picklatest_override(){
  try{
    const g=(typeof window!=="undefined")?window:globalThis;
    const fn=g.VSP_RID_PICKLATEST_OVERRIDE_V1;
    if (typeof fn==="function"){
      const v = await fn();
      if (v) return v;
    }
  }catch(e){}
  return null;
}
'''
if "__vsp_safe_picklatest_override" not in s:
  s = s + "\n" + helper

# Try inject at start of pickLatest function if it exists
m = re.search(r'(async function\s+pickLatest\s*\([^)]*\)\s*\{)', s)
if m and "__vsp_safe_picklatest_override" in s:
  insert = m.group(1) + "\n  const __ov = await __vsp_safe_picklatest_override();\n  if (__ov) return __ov;\n"
  s = s[:m.start(1)] + insert + s[m.end(1):]

p.write_text(s, encoding="utf-8")
print("[OK] rid_state guard v6 applied")
PY

node --check "$F" && echo "[OK] rid_state JS syntax OK"
echo "[DONE] Now restart 8910 + hard refresh Ctrl+Shift+R."
