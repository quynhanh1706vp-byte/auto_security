#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_sanitize_v4_${TS}" && echo "[BACKUP] $F.bak_sanitize_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 0) Remove garbage whole-line tokens introduced by broken regex patches
s = re.sub(r'^\s*\$1\s*;?\s*$', '', s, flags=re.M)
s = re.sub(r'^\s*\\1\s*;?\s*$', '', s, flags=re.M)

# 1) Remove any previous commercial shim blocks (avoid stacking)
for (BEGIN, END) in [
  ("/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_BEGIN */", "/* VSP_RIDSTATE_COMMERCIAL_SHIM_V1_END */"),
  ("/* VSP_RIDSTATE_COMMERCIAL_SHIM_V3_BEGIN */", "/* VSP_RIDSTATE_COMMERCIAL_SHIM_V3_END */"),
  ("/* VSP_RIDSTATE_COMMERCIAL_SHIM_V4_BEGIN */", "/* VSP_RIDSTATE_COMMERCIAL_SHIM_V4_END */"),
]:
  s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END)+r"\s*", "", s, flags=re.S)

# 2) Sanitize bare-identifier $1 usages conservatively (do NOT touch "$1" strings)
#    Replace patterns like "= $1", "return $1", "( $1", ", $1", ": $1"
repls = [
  (r'(\breturn\s+)\$1\b', r'\1null'),
  (r'([=:\(,\[]\s*)\$1\b', r'\1null'),
  (r'(\bvar\s+\w+\s*=\s*)\$1\b', r'\1null'),
  (r'(\blet\s+\w+\s*=\s*)\$1\b', r'\1null'),
  (r'(\bconst\s+\w+\s*=\s*)\$1\b', r'\1null'),
]
for pat, rep in repls:
  s = re.sub(pat, rep, s)

# 3) Inject EARLY safety (must run before any call to VSP_RID_PICKLATEST_OVERRIDE_V1)
early = """\
  /* VSP_RIDSTATE_COMMERCIAL_SHIM_V4_BEGIN */
  // commercial safety: ensure st exists + pickLatest override is ALWAYS a function (before first use)
  var st = (window.__vspRidState || (window.__vspRidState = {}));
  try {
    if (typeof window.VSP_RID_PICKLATEST_OVERRIDE_V1 !== 'function') {
      window.VSP_RID_PICKLATEST_OVERRIDE_V1 = function(items){
        try { if (typeof pickLatest === 'function') return pickLatest(items); } catch(e) {}
        return (items && items[0]) ? items[0] : null;
      };
    }
  } catch(e) {}
  // bind a local symbol so calls inside this IIFE never hit a non-function global
  var VSP_RID_PICKLATEST_OVERRIDE_V1 = window.VSP_RID_PICKLATEST_OVERRIDE_V1;
  /* VSP_RIDSTATE_COMMERCIAL_SHIM_V4_END */
"""

# Insert after 'use strict'; else near top of IIFE
if "'use strict'" in s:
  s = re.sub(r"('use strict'\s*;\s*)", r"\1\n"+early+"\n", s, count=1)
else:
  s = re.sub(r"(\(function\(\)\s*\{\s*)", r"\1\n"+early+"\n", s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] rid_state sanitized + early override forced (v4)")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"
echo "[DONE] rid_state v4 applied. Hard refresh Ctrl+Shift+R."
