#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

# ---------- [1] patch rid_state: ensure `st` exists + define override symbol ----------
F1="static/js/vsp_rid_state_v1.js"
[ -f "$F1" ] || { echo "[ERR] missing $F1"; exit 2; }
cp -f "$F1" "$F1.bak_referr_fix_${TS}" && echo "[BACKUP] $F1.bak_referr_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_BEGIN */"
END  ="/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_END */"
s=re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), "", s, flags=re.S)

# inject `var st = ...` right after 'use strict' (or near top)
if "'use strict'" in s:
    s = re.sub(r"('use strict'\s*;\s*)",
               r"\1\n  var st = (window.__vspRidState || (window.__vspRidState = {}));\n",
               s, count=1)
else:
    # fallback inject near top of IIFE
    s = re.sub(r"(\(function\(\)\s*\{\s*)",
               r"\1\n  var st = (window.__vspRidState || (window.__vspRidState = {}));\n",
               s, count=1)

# append shim near end but before IIFE close if possible
shim = f"""
  {BEGIN}
  // commercial safety: always define override hook + expose minimal state
  try {{
    window.VSP_RID_PICKLATEST_OVERRIDE_V1 = window.VSP_RID_PICKLATEST_OVERRIDE_V1 || function(items) {{
      try {{
        if (typeof pickLatest === 'function') return pickLatest(items);
      }} catch(e) {{}}
      return (items && items[0]) ? items[0] : null;
    }};
    window.VSP_RID_STATE_V1 = window.VSP_RID_STATE_V1 || {{}};
    window.VSP_RID_STATE_V1.st = st;
  }} catch(e) {{}}
  {END}
"""
if "})();" in s:
    s = s.replace("})();", shim + "\n})();", 1)
else:
    s = s.rstrip() + "\n" + shim + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] rid_state shim injected")
PY

node --check "$F1" >/dev/null && echo "[OK] rid_state JS syntax OK"

# ---------- [2] patch rule_overrides: guard missing override symbol ----------
F2="static/js/vsp_rule_overrides_tab_v1.js"
[ -f "$F2" ] || { echo "[ERR] missing $F2"; exit 2; }
cp -f "$F2" "$F2.bak_referr_fix_${TS}" && echo "[BACKUP] $F2.bak_referr_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_rule_overrides_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RULEOVERRIDES_GUARD_V1_BEGIN */"
END  ="/* VSP_RULEOVERRIDES_GUARD_V1_END */"
s=re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), "", s, flags=re.S)

guard = f"""
{BEGIN}
// commercial safety: don't crash if rid override hook not present
try {{
  if (!window.VSP_RID_PICKLATEST_OVERRIDE_V1) {{
    window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items) {{
      return (items && items[0]) ? items[0] : null;
    }};
  }}
}} catch(e) {{}}
{END}
"""

# put guard near top (after 'use strict' if present)
if "'use strict'" in s:
    s = re.sub(r"('use strict'\s*;\s*)", r"\\1\n"+guard+"\n", s, count=1)
else:
    s = guard + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] rule_overrides guard injected")
PY

node --check "$F2" >/dev/null && echo "[OK] rule_overrides JS syntax OK"

echo "[DONE] Patched console ReferenceErrors (rid_state + rule_overrides). Hard refresh Ctrl+Shift+R."
