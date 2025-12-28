#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_crashfix_v7_${TS}" && echo "[BACKUP] $F.bak_crashfix_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RID_PICKLATEST_CRASHFIX_V7_BEGIN */"
END  ="/* VSP_RID_PICKLATEST_CRASHFIX_V7_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s)

block = r'''/* VSP_RID_PICKLATEST_CRASHFIX_V7_BEGIN */
(function(){
  try{
    const G = (typeof globalThis !== "undefined") ? globalThis : window;
    // Always keep an override callable
    if (typeof G.VSP_RID_PICKLATEST_OVERRIDE_V1 !== "function"){
      G.VSP_RID_PICKLATEST_OVERRIDE_V1 = async function(){ return null; };
    }
    // Safe caller (never throws to break page)
    G.__VSP_CALL_PICKLATEST_OVERRIDE = async function(){
      try{
        const fn = G.VSP_RID_PICKLATEST_OVERRIDE_V1;
        if (typeof fn === "function") return await fn();
        return null;
      }catch(e){
        console.warn("[VSP_RID_STATE_V7] override failed:", e);
        return null;
      }
    };
  }catch(e){
    console.warn("[VSP_RID_STATE_V7] init failed:", e);
  }
})();
/* VSP_RID_PICKLATEST_CRASHFIX_V7_END */
'''

# Inject early: after 'use strict' if possible, else prepend
if "use strict" in s:
  s = re.sub(r"(['\"]use strict['\"];?\s*)", r"\1\n"+block+"\n", s, count=1)
else:
  s = block + "\n" + s

# Replace ANY direct calls to override with safe caller
# (covers VSP_RID_PICKLATEST_OVERRIDE_V1(), window.*, globalThis.*)
s = re.sub(r"\b(window|globalThis)\.VSP_RID_PICKLATEST_OVERRIDE_V1\s*\(\s*\)",
           r"globalThis.__VSP_CALL_PICKLATEST_OVERRIDE()", s)
s = re.sub(r"\bVSP_RID_PICKLATEST_OVERRIDE_V1\s*\(\s*\)",
           r"globalThis.__VSP_CALL_PICKLATEST_OVERRIDE()", s)

p.write_text(s, encoding="utf-8")
print("[OK] patched rid_state crashfix v7 + replaced override calls")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"

# ---- Fix templates: bump cache param + remove stray /static/js/P... ----
fix_tpl () {
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_fixrid_v7_${TS}" && echo "[BACKUP] $T.bak_fixrid_v7_${TS}"

  python3 - <<PY
import os, re
from pathlib import Path
ts=os.environ.get("TS","")
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")

# Remove any stray script tags like /static/js/Pxxxx...
s=re.sub(r'\n?\s*<script[^>]+src="/static/js/P[^"]*"[^>]*>\s*</script>\s*', "\n", s, flags=re.I)

# Force rid_state src with fresh cache param
s=re.sub(r'(<script\s+src="/static/js/vsp_rid_state_v1\.js)(\?v=[^"]*)?("></script>)',
         r'\\1?v='+ts+r'\\3', s, flags=re.I)

p.write_text(s, encoding="utf-8")
print("[OK] template rid_state src fixed:", p)
PY
}

export TS
fix_tpl "templates/vsp_4tabs_commercial_v1.html"
fix_tpl "templates/vsp_dashboard_2025.html"

echo "[DONE] V7 applied. Restart 8910 + hard refresh Ctrl+Shift+R."
