#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dom_reports_${TS}"
echo "[BACKUP] ${F}.bak_dom_reports_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_REPORTS_DOM_ENHANCER_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon = r'''
/* VSP5_REPORTS_DOM_ENHANCER_P0_V1 */
(function(){
  'use strict';
  if (window.__VSP5_REPORTS_DOM_ENHANCER_P0_V1) return;
  window.__VSP5_REPORTS_DOM_ENHANCER_P0_V1 = true;

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && (el.textContent||"").trim()) || ""; }

  // CSS
  try{
    if(!document.getElementById("vsp5_reports_dom_css")){
      const st=document.createElement("style");
      st.id="vsp5_reports_dom_css";
      st.textContent = `
        .vsp5-actions{white-space:nowrap; display:flex; gap:6px; align-items:center}
        .vsp5-btn{display:inline-flex;align-items:center;gap:6px;padding:4px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);
                 text-decoration:none;font-size:12px; line-height:1; user-select:none}
        .vsp5-btn.off{opacity:.45;cursor:not-allowed}
        .vsp5-pill{display:inline-flex;align-items:center;padding:2px 8px;border-radius:999px;font-size:11px;border:1px solid rgba(255,255,255,.14);opacity:.9}
        .vsp5-pill.off{opacity:.35}
        .vsp5-toast{position:fixed; right:16px; top:16px; z-index:9999; background:rgba(10,15,25,.92); color:#e7eefc;
                   border:1px solid rgba(255,255,255,.14); padding:10px 12px; border-radius:12px; font-size:13px; max-width:360px}
      `;
      document.head.appendChild(st);
    }
  }catch(e){}

  let toastTimer=null;
  function toast(msg){
    try{
      let el=document.getElementById("vsp5_toast");
      if(!el){
        el=document.createElement("div");
        el.id="vsp5_toast";
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

  async function headOK(url){
    try{
      const r = await fetch(url, {method:"HEAD", cache:"no-store"});
      return r && r.ok;
    }catch(e){
      return false;
    }
  }

  async function openIfOk(url, label){
    const ok = await headOK(url);
    if(!ok){
      toast(label + " missing (404)");
      return;
    }
    window.open(url, "_blank", "noopener");
  }

  // Fetch run has-map (limit high for UI)
  let runMap = new Map();
  async function refreshRunMap(){
    try{
      const u = new URL("/api/vsp/runs", window.location.origin);
      u.searchParams.set("limit","500");
      const r = await fetch(u.toString(), {cache:"no-store"});
      const j = await r.json();
      const items = (j && j.items) || [];
      const m = new Map();
      for(const it of items){
        if(!it) continue;
        const rid = it.run_id || it.rid;
        if(!rid) continue;
        m.set(String(rid), it.has || {});
      }
      runMap = m;
      return true;
    }catch(e){
      return false;
    }
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
    // click handler added later via dataset
    return `<a class="${cls}" href="${url}" data-vsp5-open="1" data-vsp5-label="${label}"${title}>${label}</a>`;
  }

  function renderReportsCell(rid, has){
    has = has || {};
    // prefer has.*_path if present
    const htmlUrl = has.html_path || (has.html ? rf(rid, "reports/index.html") : "");
    const jsonUrl = has.json_path || rf(rid, "reports/findings_unified.json");
    const sumUrl  = has.summary_path || rf(rid, "reports/run_gate_summary.json");
    const txtUrl  = has.txt_path || rf(rid, "reports/SUMMARY.txt");

    // allow JSON/SUM/TXT as clickable but will HEAD-check
    const htmlOk = !!htmlUrl && !!has.html;
    const jsonOk = true;
    const sumOk  = true;
    const txtOk  = true;

    return `
      <div class="vsp5-actions">
        ${btn("HTML", htmlUrl||"#", htmlOk, htmlOk?"":"missing HTML")}
        ${btn("JSON", jsonUrl, jsonOk, "unified findings")}
        ${btn("SUM",  sumUrl,  sumOk,  "gate summary")}
        ${btn("TXT",  txtUrl,  txtOk,  "summary text")}
        ${pill("H", !!has.html)}
        ${pill("J", !!has.json)}
        ${pill("S", !!has.summary)}
      </div>
    `;
  }

  function enhanceTableOnce(){
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

      const has = runMap.get(rid) || {};
      // avoid rework if already enhanced
      if(tds[idxRep].dataset.vsp5Enhanced === "1") continue;

      tds[idxRep].innerHTML = renderReportsCell(rid, has);
      tds[idxRep].dataset.vsp5Enhanced = "1";
    }

    // attach click handler (delegation)
    if(!t.dataset.vsp5ClickBound){
      t.addEventListener("click", async (ev)=>{
        const a = ev.target && ev.target.closest && ev.target.closest('a[data-vsp5-open="1"]');
        if(!a) return;
        ev.preventDefault();
        const url = a.getAttribute("href");
        const label = a.getAttribute("data-vsp5-label") || "FILE";
        await openIfOk(url, label);
      }, true);
      t.dataset.vsp5ClickBound = "1";
    }

    return true;
  }

  // Debounced enhancer
  let timer=null;
  function schedule(){
    if(timer) return;
    timer=setTimeout(async ()=>{
      timer=null;
      if(runMap.size === 0) await refreshRunMap();
      enhanceTableOnce();
    }, 250);
  }

  // Observe DOM changes in Runs tab area
  try{
    const obs = new MutationObserver(()=>schedule());
    obs.observe(document.documentElement, {subtree:true, childList:true});
  }catch(e){}

  // Also refresh map periodically (keepalive style)
  setInterval(()=>{ refreshRunMap().then(()=>schedule()); }, 8000);

  // First run
  refreshRunMap().then(()=>schedule());

})();
'''
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended DOM enhancer:", MARK)
PY

command -v node >/dev/null 2>&1 && node --check "$F" && echo "[OK] node --check OK" || true
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restart done; Ctrl+F5 /vsp5 → Runs & Reports."
