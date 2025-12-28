#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

# Find your UI extras file (you have vsp_ui_extras_v25.js loaded)
F="$(grep -RIl "VSP_UI_EXTRAS" . | grep -E "vsp_ui_extras_.*\.js$" | head -n 1 || true)"
[ -n "$F" ] || { echo "[ERR] cannot find vsp_ui_extras*.js"; exit 2; }

cp -f "$F" "$F.bak_p0_ids_${TS}"
echo "[BACKUP] $F.bak_p0_ids_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("""'"$F"'""")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "P0_DOM_FORM_IDS_FIX_V1"
if MARK not in s:
    addon = r"""
/* P0_DOM_FORM_IDS_FIX_V1: auto-fix duplicate ids + missing name/id for form fields */
(function(){
  'use strict';
  function run(){
    try{
      // 1) Fix duplicate IDs
      const byId = {};
      const all = Array.from(document.querySelectorAll("[id]"));
      for (const el of all){
        const id = el.getAttribute("id");
        if (!id) continue;
        byId[id] = byId[id] || [];
        byId[id].push(el);
      }
      for (const id of Object.keys(byId)){
        const arr = byId[id];
        if (arr.length <= 1) continue;
        // keep first, rename others
        for (let i=1;i<arr.length;i++){
          const newId = id + "__dup" + i;
          arr[i].setAttribute("id", newId);
          // if there is a label for old id near it, best-effort adjust
          const lab = document.querySelector('label[for="'+id+'"]');
          if (lab && i===1) { /* keep first label */ }
        }
        try{ console.info("[P0_IDS] fixed duplicate id:", id, "count=", arr.length); }catch(_){}
      }

      // 2) Ensure form controls have id or name (Chrome Issues)
      const ctrls = Array.from(document.querySelectorAll("input,select,textarea"));
      let k = 0;
      for (const el of ctrls){
        const tag = (el.tagName||"x").toLowerCase();
        const id = el.getAttribute("id");
        const name = el.getAttribute("name");
        if ((!id || !id.trim()) && (!name || !name.trim())){
          const nid = "vsp_auto_" + tag + "_" + (++k);
          el.setAttribute("id", nid);
          el.setAttribute("name", nid);
        } else if ((!name || !name.trim()) && id && id.trim()){
          el.setAttribute("name", id.trim());
        } else if ((!id || !id.trim()) && name && name.trim()){
          el.setAttribute("id", name.trim());
        }
      }
    }catch(e){
      try{ console.warn("[P0_IDS] fixer error:", e && e.message ? e.message : e); }catch(_){}
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, {once:true});
  } else {
    run();
  }
})();
"""
    s = s + "\n" + addon
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", MARK)
else:
    print("[OK] already patched")
PY

node --check "$F" >/dev/null && echo "[OK] node --check $F"
echo "[DONE] ids fix patch => $F"
