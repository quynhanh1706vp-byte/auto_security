#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_defineprop_v8_${TS}" && echo "[BACKUP] $F.bak_defineprop_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# remove old blocks if any
for tag in [
  ("/* VSP_RID_PICKLATEST_CRASHFIX_V7_BEGIN */","/* VSP_RID_PICKLATEST_CRASHFIX_V7_END */"),
  ("/* VSP_RID_PICKLATEST_GUARD_V6_BEGIN */","/* VSP_RID_PICKLATEST_GUARD_V6_END */"),
  ("/* VSP_RID_PICKLATEST_FORCE_V5_BEGIN */","/* VSP_RID_PICKLATEST_FORCE_V5_END */"),
]:
  b,e=tag
  s=re.sub(re.escape(b)+r"[\s\S]*?"+re.escape(e)+r"\n?", "", s)

BEGIN="/* VSP_RID_OVERRIDE_DEFINEPROP_V8_BEGIN */"
END  ="/* VSP_RID_OVERRIDE_DEFINEPROP_V8_END */"

block = r'''/* VSP_RID_OVERRIDE_DEFINEPROP_V8_BEGIN */
(function(){
  try{
    const G = (typeof globalThis !== "undefined") ? globalThis : window;

    // robust safe fallback function
    const _fallback = async function(){ return null; };

    // define getter/setter so it can NEVER become non-function
    let _fn = null;
    try{
      const desc = Object.getOwnPropertyDescriptor(G, "VSP_RID_PICKLATEST_OVERRIDE_V1");
      // if already defined but configurable==false, just force value to function
      if (desc && desc.configurable === false){
        if (typeof G.VSP_RID_PICKLATEST_OVERRIDE_V1 !== "function") G.VSP_RID_PICKLATEST_OVERRIDE_V1 = _fallback;
      } else {
        Object.defineProperty(G, "VSP_RID_PICKLATEST_OVERRIDE_V1", {
          configurable: true,
          enumerable: true,
          get: function(){ return (typeof _fn === "function") ? _fn : _fallback; },
          set: function(v){
            if (typeof v === "function") _fn = v;
            else _fn = null; // ignore bad assignments
          }
        });
        // initialize
        G.VSP_RID_PICKLATEST_OVERRIDE_V1 = G.VSP_RID_PICKLATEST_OVERRIDE_V1; // trigger getter
      }
    }catch(e){
      // fallback if defineProperty fails for any reason
      if (typeof G.VSP_RID_PICKLATEST_OVERRIDE_V1 !== "function") G.VSP_RID_PICKLATEST_OVERRIDE_V1 = _fallback;
    }

    // universal safe caller (even if rid_state still calls directly somewhere)
    G.__VSP_CALL_PICKLATEST_OVERRIDE = async function(){
      try{
        const fn = G.VSP_RID_PICKLATEST_OVERRIDE_V1;
        if (typeof fn === "function") return await fn();
        return null;
      }catch(e){
        console.warn("[VSP_RID_STATE_V8] override failed:", e);
        return null;
      }
    };
  }catch(e){
    console.warn("[VSP_RID_STATE_V8] init failed:", e);
  }
})();
/* VSP_RID_OVERRIDE_DEFINEPROP_V8_END */
'''

# prepend at very top to beat any later code
s = block + "\n" + s

# also rewrite obvious direct calls (best-effort)
s = re.sub(r"\b(window|globalThis)\.VSP_RID_PICKLATEST_OVERRIDE_V1\s*\(\s*\)",
           r"globalThis.__VSP_CALL_PICKLATEST_OVERRIDE()", s)
s = re.sub(r"\bVSP_RID_PICKLATEST_OVERRIDE_V1\s*\(\s*\)",
           r"globalThis.__VSP_CALL_PICKLATEST_OVERRIDE()", s)

p.write_text(s, encoding="utf-8")
print("[OK] V8 defineProperty guard injected + direct calls rewritten")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"

# bump cache param in vsp4 template (so browser can't load old file)
T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] && cp -f "$T" "$T.bak_ridv8_${TS}" && echo "[BACKUP] $T.bak_ridv8_${TS}"
python3 - <<PY
import re, os
from pathlib import Path
ts=os.environ.get("TS","")
p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")
s=re.sub(r'(<script\s+src="/static/js/vsp_rid_state_v1\.js)(\?v=[^"]*)?("></script>)',
         r'\\1?v='+ts+r'\\3', s, flags=re.I)
p.write_text(s, encoding="utf-8")
print("[OK] bumped rid_state cache in vsp4 template")
PY

echo "[DONE] V8 applied. Restart 8910 + hard refresh Ctrl+Shift+R."
