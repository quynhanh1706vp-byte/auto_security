#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_panel_v4_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_panel_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_PANEL_V4"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

append = r'''
/* ===== VSP_P1_DASH_MINICHARTS_PANEL_V4 =====
   Always render a mini-charts panel INSIDE #vsp-dashboard-main (no heading dependency).
   Data source: /api/vsp/run_file_allow?rid=...&path=findings_unified.json
   Expose: window.__vspMiniPanelV4Refresh()
*/
(function(){
  "use strict";

  function esc(s){
    try{ return String(s ?? "").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])); }
    catch(e){ return ""; }
  }
  function getRID(){
    try{
      const u=new URL(window.location.href);
      const rid=u.searchParams.get("rid");
      if (rid) return rid;
    }catch(e){}
    try{
      const t=document.body.innerText||"";
      const m=t.match(/\bVSP_CI_\d{8}_\d{6}\b/);
      if(m) return m[0];
    }catch(e){}
    return "";
  }
  async function fetchText(url, timeoutMs){
    const ctrl=new AbortController();
    const to=setTimeout(()=>ctrl.abort(), timeoutMs||8000);
    try{
      const r=await fetch(url,{credentials:"same-origin",cache:"no-store",signal:ctrl.signal});
      return await r.text();
    } finally { clearTimeout(to); }
  }
  async function fetchJSON(url, timeoutMs){
    const txt = await fetchText(url, timeoutMs);
    try{ return JSON.parse(txt); }catch(e){ return {ok:false, err:"NOT_JSON", _head:(txt||"").slice(0,200)}; }
  }

  async function fetchFindingsAllow(rid){
    const paths=["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"];
    for(const path of paths){
      const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}&limit=5000`;
      const j = await fetchJSON(u, 12000);
      const arr = (j && (j.findings||j.items)) || [];
      if(j && j.ok===true && Array.isArray(arr) && arr.length){
        return {ok:true, from:(j.from||path), findings:arr};
      }
    }
    return {ok:false, from:"", findings:[]};
  }

  function sevRank(s){
    switch(String(s||"").toUpperCase()){
      case "CRITICAL": return 0;
      case "HIGH": return 1;
      case "MEDIUM": return 2;
      case "LOW": return 3;
      case "INFO": return 4;
      case "TRACE": return 5;
      default: return 9;
    }
  }

  function compute(findings){
    const sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,OTHER:0};
    const byTool = {};
    const cweCount = {};
    const bucketTool = {};
    const risk = [];

    for(const f of (findings||[])){
      const sev = String((f.severity||f.sev||"")||"").toUpperCase();
      const tool = String((f.tool||f.engine||"")||"unknown");
      const cwe = (f.cwe ?? f.cwe_id ?? f.cweId ?? null);
      const title = f.title || f.name || f.rule_id || f.id || "Finding";
      const file = f.file || f.path || f.location || f.target || "";

      if(sevCount[sev]!==undefined) sevCount[sev]++; else sevCount.OTHER++;

      if(!byTool[tool]) byTool[tool]={TOTAL:0,CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,OTHER:0};
      byTool[tool].TOTAL++;
      if(byTool[tool][sev]!==undefined) byTool[tool][sev]++; else byTool[tool].OTHER++;

      bucketTool[tool]=(bucketTool[tool]||0)+1;

      if(cwe){
        const k=String(cwe);
        cweCount[k]=(cweCount[k]||0)+1;
      }

      risk.push({sev, tool, title, file});
    }

    risk.sort((a,b)=>{
      const ra=sevRank(a.sev), rb=sevRank(b.sev);
      if(ra!==rb) return ra-rb;
      return String(a.title).localeCompare(String(b.title));
    });

    const topCWE = = Object.entries(cweCount).sort((a,b)=>b[1]-a[1]).slice(0,8);
    const toolBuckets = Object.entries(bucketTool).sort((a,b)=>b[1]-a[1]).slice(0,10);

    const critHighByTool = Object.entries(byTool)
      .map(([t,v])=>({tool:t, crit:v.CRITICAL||0, high:v.HIGH||0, total:v.TOTAL||0}))
      .filter(x=> (x.crit+x.high)>0)
      .sort((a,b)=>(b.crit+b.high)-(a.crit+a.high))
      .slice(0,10);

    return {sevCount, topCWE, toolBuckets, critHighByTool, topRisk:risk.slice(0,8)};
  }

  function mkPanel(){
    const host = document.getElementById("vsp-dashboard-main") || document.body;
    if(!host) return null;

    let ex = document.getElementById("vsp-mini-panel-v4");
    if(ex) return ex;

    const wrap = document.createElement("div");
    wrap.id = "vsp-mini-panel-v4";
    wrap.style.margin="14px 0 18px 0";
    wrap.style.padding="12px 12px";
    wrap.style.border="1px solid rgba(255,255,255,0.10)";
    wrap.style.borderRadius="14px";
    wrap.style.background="rgba(255,255,255,0.02)";

    wrap.innerHTML = `
      <div style="display:flex; align-items:center; justify-content:space-between; gap:10px;">
        <div style="font-weight:600; letter-spacing:.2px;">Mini Charts (fallback)</div>
        <div id="vsp-mini-panel-v4-status" style="opacity:.75; font-size:12px;">init…</div>
      </div>
      <div style="height:10px;"></div>
      <div id="vsp-mini-panel-v4-body" style="font-size:12px; line-height:1.35; opacity:.95;">
        <div style="opacity:.75;">Loading…</div>
      </div>
    `;
    host.appendChild(wrap);
    return wrap;
  }

  function renderTable(rows){
    let h='<table style="width:100%; border-collapse:collapse;">';
    for(const r of rows){
      h+='<tr>';
      for(const c of r){
        h+=`<td style="padding:3px 6px; border-bottom:1px solid rgba(255,255,255,0.06); vertical-align:top;">${c}</td>`;
      }
      h+='</tr>';
    }
    h+='</table>';
    return h;
  }

  function render(panel, rid, from, stats){
    const st = panel.querySelector("#vsp-mini-panel-v4-status");
    const body = panel.querySelector("#vsp-mini-panel-v4-body");
    if(st) st.textContent = `RID=${rid} • from=${from}`;

    const s = stats.sevCount || {};
    const rowsSev = [
      ["Severity","Count"],
      ["CRITICAL", String(s.CRITICAL||0)],
      ["HIGH", String(s.HIGH||0)],
      ["MEDIUM", String(s.MEDIUM||0)],
      ["LOW", String(s.LOW||0)],
      ["INFO", String(s.INFO||0)],
      ["TRACE", String(s.TRACE||0)],
    ];

    const rowsCH = [["Tool","CRITICAL","HIGH","TOTAL"]];
    for(const it of (stats.critHighByTool||[])){
      rowsCH.push([esc(it.tool), String(it.crit||0), String(it.high||0), String(it.total||0)]);
    }

    const rowsCWE = [["CWE","Count"]];
    for(const [c,n] of (stats.topCWE||[])){
      rowsCWE.push([esc(c), String(n)]);
    }

    const rowsBuckets = [["Tool","Count"]];
    for(const [t,n] of (stats.toolBuckets||[])){
      rowsBuckets.push([esc(t), String(n)]);
    }

    const rowsRisk = [["Sev","Tool","Title","File"]];
    for(const it of (stats.topRisk||[])){
      rowsRisk.push([esc(it.sev), esc(it.tool), esc(it.title), esc(it.file)]);
    }

    if(body){
      body.innerHTML = `
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
          <div>
            <div style="opacity:.75; margin-bottom:6px;">Severity Distribution</div>
            ${renderTable(rowsSev)}
          </div>
          <div>
            <div style="opacity:.75; margin-bottom:6px;">Critical/High by Tool</div>
            ${rowsCH.length>1 ? renderTable(rowsCH) : `<div style="opacity:.75;">No CRITICAL/HIGH</div>`}
          </div>
          <div>
            <div style="opacity:.75; margin-bottom:6px;">Top CWE Exposure</div>
            ${rowsCWE.length>1 ? renderTable(rowsCWE) : `<div style="opacity:.75;">No CWE</div>`}
          </div>
          <div>
            <div style="opacity:.75; margin-bottom:6px;">By Tool Buckets</div>
            ${rowsBuckets.length>1 ? renderTable(rowsBuckets) : `<div style="opacity:.75;">No buckets</div>`}
          </div>
        </div>
        <div style="height:12px;"></div>
        <div style="opacity:.75; margin-bottom:6px;">Top Risk Findings</div>
        ${rowsRisk.length>1 ? renderTable(rowsRisk) : `<div style="opacity:.75;">No findings</div>`}
      `;
    }
  }

  async function refresh(){
    const rid = getRID();
    const panel = mkPanel();
    if(!panel) return;

    const st = panel.querySelector("#vsp-mini-panel-v4-status");
    const body = panel.querySelector("#vsp-mini-panel-v4-body");

    if(!rid){
      if(st) st.textContent="no RID";
      if(body) body.innerHTML='<div style="opacity:.75;">No RID found on page URL. Try /vsp5?rid=...</div>';
      return;
    }

    if(st) st.textContent=`RID=${rid} • fetching…`;
    if(body) body.innerHTML='<div style="opacity:.75;">Fetching findings_unified.json…</div>';

    const res = await fetchFindingsAllow(rid);
    if(!res.ok || !(res.findings||[]).length){
      if(st) st.textContent=`RID=${rid} • no findings (allowlist)`;
      if(body) body.innerHTML='<div style="opacity:.75;">Could not load findings via run_file_allow. Check server allowlist.</div>';
      return;
    }

    render(panel, rid, res.from, compute(res.findings));
  }

  // run a few times to win race
  let tries=0;
  function loop(){
    tries++;
    refresh();
    if(tries<6) setTimeout(loop, 900);
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(loop, 120));
  } else {
    setTimeout(loop, 120);
  }

  window.__vspMiniPanelV4Refresh = function(){ loop(); };
})();
'''
p.write_text(s + ("\n" if not s.endswith("\n") else "") + append, encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5?rid=VSP_CI_20251218_114312"
grep -n "VSP_P1_DASH_MINICHARTS_PANEL_V4" "$JS" | head
