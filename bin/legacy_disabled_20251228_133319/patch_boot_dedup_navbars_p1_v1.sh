#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node"; exit 2; }

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dedupnav_${TS}"
echo "[BACKUP] ${JS}.bak_dedupnav_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DEDUP_NAVBARS_P1_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

inject = r'''
/* VSP_P1_DEDUP_NAVBARS_P1_V1 */
(function(){
  function _txt(el){
    try{ return (el.innerText||"").toLowerCase(); }catch(_){ return ""; }
  }
  function _hasAllTabs(t){
    // heuristic: must contain at least 3 of these to be considered a nav/tabs bar
    const keys = ["dashboard","runs","reports","data source","settings","rule overrides"];
    let hit=0;
    for(const k of keys){ if (t.includes(k)) hit++; }
    return hit >= 3;
  }
  function _dedup(){
    try{
      if (window.__vsp_p1_dedup_navbars_p1_v1) return;
      window.__vsp_p1_dedup_navbars_p1_v1 = true;

      // style for hiding
      if (!document.getElementById("VSP_P1_DEDUP_NAV_STYLE")){
        const st=document.createElement("style");
        st.id="VSP_P1_DEDUP_NAV_STYLE";
        st.textContent = ".vspP1NavHidden{display:none !important;} body{scroll-behavior:auto;}";
        document.head.appendChild(st);
      }

      // candidate containers
      const cand = [];
      const nodes = document.querySelectorAll("nav, header, .top, .tabs, .navbar, .nav, .tabbar, .wrap");
      nodes.forEach(el=>{
        const t=_txt(el);
        if (!_hasAllTabs(t)) return;
        // avoid picking huge containers
        const h = (el.getBoundingClientRect ? el.getBoundingClientRect().height : 0);
        if (h > 260) return;
        cand.push(el);
      });

      if (cand.length <= 1) return;

      // pick the earliest visible one on page (top-most)
      cand.sort((a,b)=>{
        const ay=a.getBoundingClientRect().top + window.scrollY;
        const by=b.getBoundingClientRect().top + window.scrollY;
        return ay-by;
      });

      const keep = cand[0];
      for (let i=1;i<cand.length;i++){
        const el=cand[i];
        if (el === keep) continue;
        el.classList.add("vspP1NavHidden");
      }

      console.info("[VSP][boot] dedup navbars:", cand.length, "kept:", keep);
    }catch(e){
      try{ console.warn("[VSP][boot] dedup navbars error", e); }catch(_){}
    }
  }

  // run after DOM is ready + after boot injects nav
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(_dedup, 50));
  } else {
    setTimeout(_dedup, 50);
  }
  // also rerun once more (some pages inject later)
  setTimeout(_dedup, 250);
})();
'''

# append near end of file (safe)
s2 = s + "\n\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS" >/dev/null
echo "[OK] node --check OK: $JS"

echo "[NEXT] restart service + hard refresh:"
echo "  sudo systemctl restart vsp-ui-8910.service"
echo "  Ctrl+F5 /vsp5"
