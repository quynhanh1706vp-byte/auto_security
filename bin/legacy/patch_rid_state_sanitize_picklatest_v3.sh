#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_sanitize_v3_${TS}" && echo "[BACKUP] $F.bak_sanitize_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 0) remove garbage lines created by bad regex replacements
#    (these cause ReferenceError: $1 is not defined)
s = re.sub(r'^\s*\$1\s*;?\s*$', '', s, flags=re.M)
s = re.sub(r'^\s*\\1\s*;?\s*$', '', s, flags=re.M)

# 1) remove any older shim blocks (avoid stacking)
blocks = [
  ("/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_BEGIN */", "/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_END */"),
]
for BEGIN, END in blocks:
  s = re.sub(re.escape(BEGIN)+r'.*?'+re.escape(END)+r'\s*', '', s, flags=re.S)

# 2) ensure state object `st` exists (some functions reference it)
if re.search(r'\bvar\s+st\b', s) is None:
  if "'use strict'" in s:
    s = re.sub(r"('use strict'\s*;\s*)",
               r"\1\n  var st = (window.__vspRidState || (window.__vspRidState = {}));\n",
               s, count=1)
  else:
    s = re.sub(r"(\(function\(\)\s*\{\s*)",
               r"\1\n  var st = (window.__vspRidState || (window.__vspRidState = {}));\n",
               s, count=1)

# 3) inject hardened shim at end: force override to be a FUNCTION (prevents TypeError)
BEGIN="/* VSP_RIDSTATE_COMMERCIAL_SHIM_V3_BEGIN */"
END  ="/* VSP_RIDSTATE_COMMERCIAL_SHIM_V3_END */"
shim = f"""
  {BEGIN}
  try {{
    // Force override hook to be a function (commercial safety)
    if (typeof window.VSP_RID_PICKLATEST_OVERRIDE_V1 !== 'function') {{
      window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items) {{
        try {{
          if (typeof pickLatest === 'function') return pickLatest(items);
        }} catch(e) {{}}
        return (items && items[0]) ? items[0] : null;
      }};
    }}
    window.VSP_RID_STATE_V1 = window.VSP_RID_STATE_V1 || {{}};
    window.VSP_RID_STATE_V1.st = (typeof st !== 'undefined') ? st : (window.__vspRidState || (window.__vspRidState = {{}}));
  }} catch(e) {{}}
  {END}
"""

# place shim before final "})();" if possible
if "})();" in s:
  s = s.replace("})();", shim + "\n})();", 1)
else:
  s = s.rstrip() + "\n" + shim + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] rid_state sanitized + override forced to function (v3)")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"
echo "[DONE] rid_state sanitize v3 applied. Hard refresh Ctrl+Shift+R."
