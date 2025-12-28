#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_picklatest_v5_${TS}" && echo "[BACKUP] $F.bak_picklatest_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RID_STATE_PICKLATEST_FORCE_V5_BEGIN */"
END  ="/* VSP_RID_STATE_PICKLATEST_FORCE_V5_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s, flags=re.M)

shim = r'''
/* VSP_RID_STATE_PICKLATEST_FORCE_V5_BEGIN */
// Force globals: override must be a function + replace pickLatest() with runs_index-based version.
(function(){
  try{
    const g = (typeof window !== 'undefined') ? window : globalThis;
    if (typeof g.VSP_RID_PICKLATEST_OVERRIDE_V1 !== 'function'){
      g.VSP_RID_PICKLATEST_OVERRIDE_V1 = async function(){ return null; };
    }
    if (typeof g.VSP_RID_PICKLATEST_OVERRIDE !== 'function'){
      g.VSP_RID_PICKLATEST_OVERRIDE = g.VSP_RID_PICKLATEST_OVERRIDE_V1;
    }
  }catch(_e){}
})();

// Hard-override pickLatest used by rid_state (fix "j is not a function")
async function pickLatest(){
  try{
    const url = '/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1';
    const res = await fetch(url, {credentials:'same-origin'});
    if (!res.ok) return null;
    const js = await res.json();
    const it = (js && js.items && js.items[0]) ? js.items[0] : null;
    const rid = it && (it.run_id || it.rid);
    return rid || null;
  }catch(_e){
    return null;
  }
}
/* VSP_RID_STATE_PICKLATEST_FORCE_V5_END */
'''.lstrip()

# Prepend shim at very top (so other tabs see the function)
s = shim + "\n" + s
p.write_text(s, encoding="utf-8")
print("[OK] injected rid_state pickLatest force v5")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"

# bump cache param in vsp4 template so browser actually reloads rid_state
T="templates/vsp_4tabs_commercial_v1.html"
if [ -f "$T" ]; then
  cp -f "$T" "$T.bak_ridstatecache_${TS}" && echo "[BACKUP] $T.bak_ridstatecache_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")
s=re.sub(r'(vsp_rid_state_v1\.js\?v=)[^"\'<> ]+', r'\1'+ "${TS}", s)
p.write_text(s, encoding="utf-8")
print("[OK] bumped rid_state cache param in vsp4 template")
PY
fi

echo "[DONE] Patch applied. Restart 8910 + hard refresh Ctrl+Shift+R."
