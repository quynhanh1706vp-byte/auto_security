#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_picklatest_override_${TS}" && echo "[BACKUP] $F.bak_picklatest_override_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_RID_PICKLATEST_OVERRIDE_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

addon = r'''
/* VSP_RID_PICKLATEST_OVERRIDE_V1: never crash, always resolve RID via API */
(function(){
  'use strict';
  function _setLS(rid){
    try{
      if(!rid) return;
      localStorage.setItem("vsp_rid_selected_v2", String(rid));
      localStorage.setItem("vsp_rid_selected", String(rid));
    }catch(e){}
  }

  async function _fetchJson(url){
    const r = await fetch(url, {headers:{'Accept':'application/json'}});
    return await r.json();
  }

  async function pickLatestSafe(){
    // 1) latest_rid_v1 (FS fallback)
    try{
      const j = await _fetchJson("/api/vsp/latest_rid_v1");
      const rid = j && (j.run_id || j.rid || j.id);
      if(rid){ _setLS(rid); return rid; }
    }catch(e){}

    // 2) runs_index_v3_fs_resolved
    try{
      const j = await _fetchJson("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=0");
      const rid = j && j.items && j.items[0] && j.items[0].run_id;
      if(rid){ _setLS(rid); return rid; }
    }catch(e){}

    return null;
  }

  // patch common globals (best-effort)
  try{
    if(window.VSP_RID_STATE_V2 && typeof window.VSP_RID_STATE_V2.pickLatest === "function"){
      window.VSP_RID_STATE_V2.pickLatest = pickLatestSafe;
    }
  }catch(e){}
  try{
    if(window.VSP_RID_STATE && typeof window.VSP_RID_STATE.pickLatest === "function"){
      window.VSP_RID_STATE.pickLatest = pickLatestSafe;
    }
  }catch(e){}

  // also expose for debugging
  window.__VSP_PICK_LATEST_SAFE = pickLatestSafe;

  console.log("[RID_OVERRIDE_V1] installed");
})();
'''
p.write_text(s.rstrip()+"\n\n"+MARK+"\n"+addon+"\n", encoding="utf-8")
print("[OK] appended pickLatest override")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_rid_state_picklatest_override_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
