#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dom_polish_${TS}"
echo "[BACKUP] ${F}.bak_dom_polish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_REPORTS_DOM_POLISH_FILTER_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# append a small patch-on-top block that upgrades CSS + adds filter behavior if enhancer exists
addon = r'''
/* VSP5_REPORTS_DOM_POLISH_FILTER_P0_V1 */
(function(){
  'use strict';
  if (window.__VSP5_REPORTS_DOM_POLISH_FILTER_P0_V1) return;
  window.__VSP5_REPORTS_DOM_POLISH_FILTER_P0_V1 = true;

  // stronger CSS (override)
  try{
    const st=document.createElement("style");
    st.id="vsp5_reports_dom_css_polish";
    st.textContent = `
      .vsp5-actions{gap:8px}
      .vsp5-btn{border:1px solid rgba(255,255,255,.18); background:rgba(255,255,255,.03)}
      .vsp5-btn:hover{background:rgba(120,200,255,.08); border-color:rgba(120,200,255,.35)}
      .vsp5-btn.off{background:transparent;border-color:rgba(255,255,255,.10)}
      .vsp5-pill{background:rgba(255,255,255,.03)}
      .vsp5-pill.off{background:transparent}
    `;
    document.head.appendChild(st);
  }catch(e){}

  function txt(el){ return (el && (el.textContent||"").trim()) || ""; }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function findRunsTable(){
    const tables = $all("table");
    for(const t of tables){
      const ths = $all("thead th", t);
      const head = ths.map(x=>txt(x).toUpperCase());
      if(head.includes("RUN ID") && head.includes("REPORTS")) return t;
    }
    return null;
  }
  function colIndexByHeader(t, name){
    const ths = $all("thead th", t);
    const up = name.toUpperCase();
    for(let i=0;i<ths.length;i++){
      if(txt(ths[i]).trim().toUpperCase()===up) return i;
    }
    return -1;
  }

  // try detect the 3 filter checkboxes by label text near top
  function readFilters(){
    const want = {html:null, json:null, sum:null};
    // heuristic: any checkbox whose parent contains "has HTML/JSON/SUM"
    const cbs = $all('input[type="checkbox"]');
    for(const cb of cbs){
      const label = (cb.closest("label") || cb.parentElement || cb).textContent || "";
      const up = label.toUpperCase();
      if(up.includes("HAS HTML")) want.html = cb.checked;
      if(up.includes("HAS JSON")) want.json = cb.checked;
      if(up.includes("HAS SUM"))  want.sum  = cb.checked;
    }
    return want;
  }

  function applyRowFilter(){
    const t = findRunsTable();
    if(!t) return;
    const idxRun = colIndexByHeader(t,"RUN ID");
    const idxRep = colIndexByHeader(t,"REPORTS");
    if(idxRun<0 || idxRep<0) return;

    const f = readFilters();
    // if all null (not found), do nothing
    if(f.html===null && f.json===null && f.sum===null) return;

    const rows = $all("tbody tr", t);
    for(const tr of rows){
      const tds = $all("td", tr);
      if(tds.length <= Math.max(idxRun, idxRep)) continue;
      const rep = tds[idxRep];

      // detect pills state from HTML (H/J/S pills)
      const pills = rep.querySelectorAll(".vsp5-pill");
      let hasH=null, hasJ=null, hasS=null;
      for(const p of pills){
        const t = (p.textContent||"").trim().toUpperCase();
        const off = p.classList.contains("off");
        if(t==="H") hasH = !off;
        if(t==="J") hasJ = !off;
        if(t==="S") hasS = !off;
      }

      let ok = true;
      if(f.html===true) ok = ok && (hasH===True || hasH===true);
      if(f.json===true) ok = ok && (hasJ===True || hasJ===true);
      if(f.sum===true)  ok = ok && (hasS===True || hasS===true);

      tr.style.display = ok ? "" : "none";
    }
  }

  // bind checkbox change
  try{
    document.addEventListener("change", (ev)=>{
      const el = ev.target;
      if(!el || el.tagName!=="INPUT" || el.type!=="checkbox") return;
      const label = (el.closest("label") || el.parentElement || el).textContent || "";
      const up = label.toUpperCase();
      if(up.includes("HAS HTML") || up.includes("HAS JSON") || up.includes("HAS SUM")){
        setTimeout(applyRowFilter, 50);
      }
    }, true);
  }catch(e){}

  // apply periodically (in case rerender)
  setInterval(applyRowFilter, 1200);
  setTimeout(applyRowFilter, 600);

})();
'''
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

command -v node >/dev/null 2>&1 && node --check "$F" && echo "[OK] node --check OK" || true
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restart done; Ctrl+F5 /vsp5."
