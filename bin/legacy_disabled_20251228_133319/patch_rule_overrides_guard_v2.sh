#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_rule_overrides_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if ! node --check "$F" >/dev/null 2>&1; then
  B="$(ls -1t static/js/vsp_rule_overrides_tab_v1.js.bak_crud_* 2>/dev/null | head -n1 || true)"
  [ -n "${B:-}" ] || { echo "[ERR] $F invalid and no bak_crud_* found"; exit 3; }
  cp -f "$B" "$F"
  echo "[RESTORE] $F <= $B"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guardv2_${TS}" && echo "[BACKUP] $F.bak_guardv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_rule_overrides_tab_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RULE_OVERRIDES_GUARD_V2_BEGIN */"
END  ="/* VSP_RULE_OVERRIDES_GUARD_V2_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s, flags=re.M)

guard = r'''
/* VSP_RULE_OVERRIDES_GUARD_V2_BEGIN */
(function(){
  'use strict';
  if (typeof window === 'undefined') return;

  window.__vspGetRidSafe = async function(){
    try{
      if (typeof window.VSP_RID_PICKLATEST_OVERRIDE_V1 === 'function'){
        const rid = await window.VSP_RID_PICKLATEST_OVERRIDE_V1();
        if (rid) return rid;
      }
    }catch(_e){}
    try{
      if (window.VSP_RID_STATE && typeof window.VSP_RID_STATE.pickLatest === 'function'){
        const rid = await window.VSP_RID_STATE.pickLatest();
        if (rid) return rid;
      }
    }catch(_e){}
    return null;
  };
})();
 /* VSP_RULE_OVERRIDES_GUARD_V2_END */
'''.lstrip()

# prepend guard near top (after first IIFE header if any)
lines=s.splitlines(True)
ins=0
for i,l in enumerate(lines[:80]):
  if "use strict" in l:
    ins=i+1
    break
lines.insert(ins, guard+"\n")
p.write_text("".join(lines), encoding="utf-8")
print("[OK] injected rule overrides guard v2")
PY

node --check "$F" >/dev/null && echo "[OK] rule_overrides JS syntax OK"
echo "[DONE] Hard refresh Ctrl+Shift+R"
