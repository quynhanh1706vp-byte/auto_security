#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node"; exit 2; }

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_hide2ndnav_${TS}"
echo "[BACKUP] ${JS}.bak_hide2ndnav_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_HIDE_SECONDARY_TABBAR_P1_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

inject=r'''
/* VSP_P1_HIDE_SECONDARY_TABBAR_P1_V1 */
(function(){
  const KEYS = ["dashboard","runs","reports","data source","settings","rule overrides"];

  function scoreText(t){
    t=(t||"").toLowerCase();
    let hit=0;
    for(const k of KEYS){ if (t.includes(k)) hit++; }
    return hit;
  }

  function hasManyButtons(el){
    try{
      const n = el.querySelectorAll("a,button").length;
      return n >= 4;
    }catch(_){ return false; }
  }

  function hideSecondary(){
    try{
      const cand=[];
      const all=document.querySelectorAll("div,section,nav,header");
      all.forEach(el=>{
        // don’t touch the top header/nav area too aggressively
        const r = el.getBoundingClientRect();
        if (!r || r.height <= 0) return;
        if (r.height > 220) return;              // avoid big containers
        const top = r.top + window.scrollY;
        const t = (el.innerText||"");
        const sc = scoreText(t);
        if (sc < 3) return;                      // must look like a tabbar
        if (!hasManyButtons(el)) return;         // must actually be a button/link bar
        cand.push({el, top, sc, h:r.height});
      });

      if (cand.length <= 1) return;

      // keep the top-most candidate (your main nav) and hide the rest
      cand.sort((a,b)=>a.top-b.top);
      const keep = cand[0].el;

      // add hide css
      if (!document.getElementById("VSP_P1_HIDE2NDNAV_STYLE")){
        const st=document.createElement("style");
        st.id="VSP_P1_HIDE2NDNAV_STYLE";
        st.textContent=".vspP1SecondaryNavHidden{display:none!important;}";
        document.head.appendChild(st);
      }

      for (let i=1;i<cand.length;i++){
        const el=cand[i].el;
        if (el===keep) continue;
        el.classList.add("vspP1SecondaryNavHidden");
      }

      console.info("[VSP][boot] hide secondary tabbars:", cand.length-1);
    }catch(e){
      try{ console.warn("[VSP][boot] hide secondary tabbar err", e); }catch(_){}
    }
  }

  if (document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(hideSecondary, 80));
  } else setTimeout(hideSecondary, 80);

  setTimeout(hideSecondary, 300); // rerun once
})();
'''

p.write_text(s + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS" >/dev/null
echo "[OK] node --check OK: $JS"

sudo systemctl restart vsp-ui-8910.service
echo "[DONE] restart ok. Ctrl+F5 /vsp5"
