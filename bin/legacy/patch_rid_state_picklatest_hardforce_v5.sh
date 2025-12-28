#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_picklatest_v5_${TS}" && echo "[BACKUP] $F.bak_picklatest_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_RID_PICKLATEST_HARDFORCE_V5_BEGIN */"
END  ="/* VSP_RID_PICKLATEST_HARDFORCE_V5_END */"

# remove old injected block (any previous v5)
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s, flags=re.M)

block = r'''
/* VSP_RID_PICKLATEST_HARDFORCE_V5_BEGIN */
(function(){
  'use strict';
  const W = (typeof window !== 'undefined') ? window : globalThis;

  function sstr(x){ return (typeof x === 'string') ? x.trim() : ''; }

  function keyFromRid(rid){
    rid = sstr(rid);
    if (!rid) return "";
    // prefer suffix _YYYYmmdd_HHMMSS if present
    const m = rid.match(/(\d{8})_(\d{6})/);
    if (m) return m[1] + m[2];
    return rid;
  }

  function pickLatestFromRuns(items){
    if (!Array.isArray(items) || items.length === 0) return null;
    let bestRid = null;
    let bestKey = "";
    for (const r of items){
      if (!r || typeof r !== 'object') continue;
      const rid = sstr(r.run_id || r.rid || r.id);
      if (!rid) continue;
      const k = keyFromRid(rid);
      if (!bestRid || k > bestKey){
        bestRid = rid;
        bestKey = k;
      }
    }
    return bestRid;
  }

  async function pickLatest(){
    // 1) if active rid already known
    try{
      const existing = sstr(W.__VSP_ACTIVE_RID || W.VSP_ACTIVE_RID || "");
      if (existing) return existing;
    }catch(_e){}

    // 2) from cached runs list
    try{
      const rid = pickLatestFromRuns(W.__vspRunsItems || []);
      if (rid) return rid;
    }catch(_e){}

    // 3) fetch runs_index and cache
    try{
      const res = await fetch('/api/vsp/runs_index_v3_fs_resolved?limit=40&hide_empty=0&filter=1', {credentials:'same-origin'});
      if (res && res.ok){
        const js = await res.json();
        const items = js.items || js.runs || js.data || [];
        W.__vspRunsItems = items;
        const rid = pickLatestFromRuns(items);
        if (rid) return rid;
      }
    }catch(_e){}

    return null;
  }

  // HARD FORCE: must always be a function
  W.VSP_RID_PICKLATEST_OVERRIDE_V1 = pickLatest;
  W.VSP_RID_STATE = W.VSP_RID_STATE || {};
  W.VSP_RID_STATE.pickLatest = pickLatest;
  W.VSP_RID_STATE.pickLatestSync = function(){ return pickLatestFromRuns(W.__vspRunsItems || []); };

  try{
    Object.defineProperty(W, 'VSP_RID_PICKLATEST_OVERRIDE_V1', { configurable:true, writable:true, value: pickLatest });
  }catch(_e){}
})();
 /* VSP_RID_PICKLATEST_HARDFORCE_V5_END */
'''.lstrip()

s = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended pickLatest hardforce v5")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"
echo "[DONE] Apply: Hard refresh Ctrl+Shift+R"
