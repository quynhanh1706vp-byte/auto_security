#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dom_reports_v2_${TS}"
echo "[BACKUP] ${F}.bak_dom_reports_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_REPORTS_DOM_ENHANCER_P0_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon = r'''
/* VSP5_REPORTS_DOM_ENHANCER_P0_V2
   - softer CSS (no neon)
   - keepalive repaint (fix "shows then disappears")
   - stronger observer: childList + characterData
*/
(function(){
  'use strict';
  if (window.__VSP5_REPORTS_DOM_ENHANCER_P0_V2) return;
  window.__VSP5_REPORTS_DOM_ENHANCER_P0_V2 = true;

  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && (el.textContent||"").trim()) || ""; }

  // softer CSS (override)
  try{
    if(!document.getElementById("vsp5_reports_dom_css_v2")){
      const st=document.createElement("style");
      st.id="vsp5_reports_dom_css_v2";
      st.textContent = `
        .vsp5-actions{white-space:nowrap; display:flex; gap:8px; align-items:center}
        .vsp5-btn{
          display:inline-flex; align-items:center; justify-content:center;
          padding:4px 10px; border-radius:10px;
          border:1px solid rgba(255,255,255,.16);
          background: rgba(255,255,255,.03);
          text-decoration:none;
          font-size:12px; line-height:1;
          color: inherit;
        }
        .vsp5-btn:hover{background: rgba(255,255,255,.07); border-color: rgba(255,255,255,.26)}
        .vsp5-btn.off{opacity:.45; cursor:not-allowed; background:transparent; border-color:rgba(255,255,255,.10)}
        .vsp5-pill{
          display:inline-flex; align-items:center;
          padding:2px 8px; border-radius:999px;
          font-size:11px;
          border:1px solid rgba(255,255,255,.14);
          background: rgba(255,255,255,.02);
          opacity:.9;
        }
        .vsp5-pill.off{opacity:.35; background:transparent}
        .vsp5-toast{
          position:fixed; right:16px; top:16px; z-index:9999;
          background:rgba(10,15,25,.92); color:inherit;
          border:1px solid rgba(255,255,255,.14);
          padding:10px 12px; border-radius:12px;
          font-size:13px; max-width:360px
        }
      `;
      document.head.appendChild(st);
    }
  }catch(e){}

  let toastTimer=null;
  function toast(msg){
    try{
      let el=document.getElementById("vsp5_toast_v2");
      if(!el){
        el=document.createElement("div");
        el.id="vsp5_toast_v2";
        el.className="vsp5-toast";
        document.body.appendChild(el);
      }
      el.textContent = msg;
      el.style.display="block";
      if(toastTimer) clearTimeout(toastTimer);
      toastTimer=setTimeout(()=>{ try{ el.style.display="none"; }catch(e){} }, 2200);
    }catch(e){}
  }

  function rf(rid, name){
    try{
      const u = new URL("/api/vsp/run_file", window.location.origin);
      u.searchParams.set("rid", rid);
      u.searchParams.set("name", name);
      return u.pathname + "?" + u.searchParams.toString();
    }catch(e){
      return "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent(name);
    }
  }

  const headCache = new Map(); // url -> Promise<boolean>
  function headOK(url){
    if(headCache.has(url)) return headCache.get(url);
    const p = (async ()=>{
      try{
        const r = await fetch(url, {method:"HEAD", cache:"no-store"});
        return !!(r && r.ok);
      }catch(e){ return false; }
    })();
    headCache.set(url, p);
    return p;
  }

  async function openIfOk(url, label){
    const ok = await headOK(url);
    if(!ok){ toast(label + " missing (404)"); return; }
    window.open(url, "_blank", "noopener");
  }

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

  function pill(label, ok){
    return `<span class="vsp5-pill ${ok?"":"off"}">${label}</span>`;
  }
  function btn(label, url, ok, tip){
    const cls = "vsp5-btn " + (ok ? "" : "off");
    const title = tip ? ` title="${String(tip).replace(/"/g,'&quot;')}"` : "";
    if(!ok) return `<span class="${cls}"${title}>${label}</span>`;
    return `<a class="${cls}" href="${url}" data-vsp5-open="1" data-vsp5-label="${label}"${title}>${label}</a>`;
  }

  function renderCell(rid){
    const htmlUrl = rf(rid, "reports/index.html");
    const jsonUrl = rf(rid, "reports/findings_unified.json");
    const sumUrl  = rf(rid, "reports/run_gate_summary.json");
    const txtUrl  = rf(rid, "reports/SUMMARY.txt");

    // pills initial = unknown(off), will be updated async
    return `
      <div class="vsp5-actions" data-rid="${rid}">
        ${btn("HTML", htmlUrl, true, "open HTML")}
        ${btn("JSON", jsonUrl, true, "unified findings")}
        ${btn("SUM",  sumUrl,  true, "gate summary")}
        ${btn("TXT",  txtUrl,  true, "summary text")}
        <span class="vsp5-pill off" data-pill="H">H</span>
        <span class="vsp5-pill off" data-pill="J">J</span>
        <span class="vsp5-pill off" data-pill="S">S</span>
      </div>
    `;
  }

  async function refreshPills(cell){
    try{
      const rid = cell.getAttribute("data-rid");
      if(!rid) return;
      const urls = {
        H: rf(rid, "reports/index.html"),
        J: rf(rid, "reports/findings_unified.json"),
        S: rf(rid, "reports/run_gate_summary.json"),
      };
      for(const k of ["H","J","S"]){
        const ok = await headOK(urls[k]);
        const pillEl = cell.querySelector(`.vsp5-pill[data-pill="${k}"]`);
        if(pillEl){
          pillEl.classList.toggle("off", !ok);
        }
      }
    }catch(e){}
  }

  function enhance(){
    const t = findRunsTable();
    if(!t) return false;

    const idxRun = colIndexByHeader(t, "RUN ID");
    const idxRep = colIndexByHeader(t, "REPORTS");
    if(idxRun < 0 || idxRep < 0) return false;

    const rows = $all("tbody tr", t);
    for(const tr of rows){
      const tds = $all("td", tr);
      if(tds.length <= Math.max(idxRun, idxRep)) continue;
      const rid = txt(tds[idxRun]);
      if(!rid) continue;

      const rep = tds[idxRep];
      // if overwritten / missing, repaint
      if(!rep.querySelector(".vsp5-actions")){
        rep.innerHTML = renderCell(rid);
        rep.dataset.vsp5EnhancedV2 = "1";
        const cell = rep.querySelector(".vsp5-actions");
        if(cell) refreshPills(cell);
      }
    }

    // bind click handler once
    if(!t.dataset.vsp5ClickBoundV2){
      t.addEventListener("click", async (ev)=>{
        const a = ev.target && ev.target.closest && ev.target.closest('a[data-vsp5-open="1"]');
        if(!a) return;
        ev.preventDefault();
        const url = a.getAttribute("href");
        const label = a.getAttribute("data-vsp5-label") || "FILE";
        await openIfOk(url, label);
      }, true);
      t.dataset.vsp5ClickBoundV2 = "1";
    }
    return true;
  }

  // Keepalive repaint (fix disappearing)
  setInterval(enhance, 700);

  // Strong observer: includes characterData (text changes)
  try{
    const obs = new MutationObserver(()=>{ setTimeout(enhance, 120); });
    obs.observe(document.documentElement, {subtree:true, childList:true, characterData:true});
  }catch(e){}

  setTimeout(enhance, 200);
  setTimeout(enhance, 900);
})();
'''
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

command -v node >/dev/null 2>&1 && node --check "$F" && echo "[OK] node --check OK" || true
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restart done; Ctrl+F5 /vsp5 → Runs & Reports."
