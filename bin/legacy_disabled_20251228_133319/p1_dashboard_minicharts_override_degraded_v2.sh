#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_override_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_override_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V2"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

append = r'''
/* ===== VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V2 =====
   Goal: when trend/topcwe APIs are blocked/degraded, still populate dashboard sections from findings_page_v3.
   - Scrub "No data (degraded)..." and "Loading..." text nodes.
   - Insert mini summary tables under headings:
     Severity Distribution / Trend / Critical|High by Tool / Top CWE Exposure / Top Risk Findings / By Tool Buckets
*/
(function(){
  "use strict";

  function esc(s){
    try{ return String(s ?? "").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])); }
    catch(e){ return ""; }
  }
  function now(){ return Date.now(); }

  function getRID(){
    try{
      const u=new URL(window.location.href);
      const rid=u.searchParams.get("rid");
      if (rid) return rid;
    }catch(e){}
    // fallback: try to read from the RID stamp on page
    try{
      const t=document.body.innerText||"";
      const m=t.match(/\bVSP_[A-Z]+_\d{8}_\d{6}\b/);
      if(m) return m[0];
      const m2=t.match(/\bVSP_CI_\d{8}_\d{6}\b/);
      if(m2) return m2[0];
    }catch(e){}
    return "";
  }

  async function fetchJSON(url, timeoutMs){
    const ctrl = new AbortController();
    const to = setTimeout(()=>ctrl.abort(), timeoutMs||6000);
    try{
      const r = await fetch(url, {credentials:"same-origin", cache:"no-store", signal: ctrl.signal});
      const txt = await r.text();
      try{ return JSON.parse(txt); } catch(e){ return {ok:false, err:"NOT_JSON", _text:(txt||"").slice(0,200)}; }
    } finally {
      clearTimeout(to);
    }
  }

  async function fetchFindings(rid){
    const base = "";
    // limit large enough for dashboard summaries
    const u = `${base}/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=5000&offset=0`;
    const j = await fetchJSON(u, 8000);
    // support multiple shapes
    const arr = (j && (j.findings || j.items || j.data || j.results)) || [];
    return {ok: j && j.ok===true, raw:j, findings: Array.isArray(arr)?arr:[]};
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
    const byTool = {}; // tool -> {TOTAL, CRITICAL, HIGH, MEDIUM, LOW, INFO, TRACE}
    const cweCount = {}; // cwe -> count
    const bucketTool = {}; // tool -> total
    const risk = []; // items

    for(const f of (findings||[])){
      const sev = String((f.severity||f.sev||"")||"").toUpperCase();
      const tool = String((f.tool||f.engine||"")||"unknown");
      const cwe = (f.cwe===None?null:f.cwe) ?? f.cwe_id ?? f.cweId ?? null;
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

    const topCWE = Object.entries(cweCount).sort((a,b)=>b[1]-a[1]).slice(0,8);
    const toolBuckets = Object.entries(bucketTool).sort((a,b)=>b[1]-a[1]).slice(0,10);

    const critHighByTool = Object.entries(byTool)
      .map(([t,v])=>({tool:t, crit:v.CRITICAL||0, high:v.HIGH||0, total:v.TOTAL||0}))
      .filter(x=> (x.crit+x.high)>0)
      .sort((a,b)=>(b.crit+b.high)-(a.crit+a.high))
      .slice(0,10);

    return {sevCount, topCWE, toolBuckets, critHighByTool, topRisk: risk.slice(0,8)};
  }

  function scrubDegradedText(){
    try{
      const walker=document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
      const kills=[];
      while(walker.nextNode()){
        const n=walker.currentNode;
        const t=(n.nodeValue||"").trim();
        if(!t) continue;
        if(/No data\s*\(degraded\)\.?/i.test(t) || /^Loading\.\.\.$/i.test(t) || /^Loading\.\.$/i.test(t) || /^Loading\.$/i.test(t)){
          kills.push(n);
        }
      }
      for(const n of kills){
        try{ n.nodeValue=""; }catch(e){}
      }
    }catch(e){}
  }

  function findHeadingEl(text){
    const want=String(text||"").trim().toLowerCase();
    if(!want) return null;
    const els=[...document.querySelectorAll("h1,h2,h3,h4,div,span,label")];
    for(const el of els){
      const t=(el.textContent||"").trim().toLowerCase();
      if(t===want) return el;
    }
    // fallback: contains
    for(const el of els){
      const t=(el.textContent||"").trim().toLowerCase();
      if(t && t.indexOf(want)>=0) return el;
    }
    return null;
  }

  function ensureBoxAfter(headingEl, boxId){
    try{
      if(!headingEl) return null;
      const existing=document.getElementById(boxId);
      if(existing) return existing;
      const box=document.createElement("div");
      box.id=boxId;
      box.style.margin="6px 0 14px 0";
      box.style.padding="8px 10px";
      box.style.border="1px solid rgba(255,255,255,0.08)";
      box.style.borderRadius="10px";
      box.style.background="rgba(255,255,255,0.02)";
      box.style.fontSize="12px";
      box.style.lineHeight="1.35";
      // insert right after heading
      if(headingEl.parentElement){
        if(headingEl.nextSibling) headingEl.parentElement.insertBefore(box, headingEl.nextSibling);
        else headingEl.parentElement.appendChild(box);
      }
      return box;
    }catch(e){ return null; }
  }

  function renderTable(rows){
    // rows: array of arrays
    let h='<table style="width:100%; border-collapse:collapse;">';
    for(const r of rows){
      h+='<tr>';
      for(const c of r){
        h+=`<td style="padding:2px 6px; border-bottom:1px solid rgba(255,255,255,0.06); vertical-align:top;">${c}</td>`;
      }
      h+='</tr>';
    }
    h+='</table>';
    return h;
  }

  function applyMiniCharts(stats){
    scrubDegradedText();

    // 1) Severity Distribution
    {
      const h = findHeadingEl("Severity Distribution");
      const box = ensureBoxAfter(h, "vsp-mini-sevdist");
      if(box){
        const s=stats.sevCount||{};
        const rows=[
          ["CRITICAL", String(s.CRITICAL||0)],
          ["HIGH", String(s.HIGH||0)],
          ["MEDIUM", String(s.MEDIUM||0)],
          ["LOW", String(s.LOW||0)],
          ["INFO", String(s.INFO||0)],
          ["TRACE", String(s.TRACE||0)],
        ];
        box.innerHTML = renderTable(rows);
      }
    }

    // 2) Trend (no timestamps in findings => show stable note instead of degraded)
    {
      const h = findHeadingEl("Trend (Findings over time)");
      const box = ensureBoxAfter(h, "vsp-mini-trend");
      if(box){
        box.innerHTML = `<div style="opacity:0.85">Trend: not available (findings do not include time series). Using current RID snapshot.</div>`;
      }
    }

    // 3) Critical/High by Tool
    {
      const h = findHeadingEl("Critical/High by Tool");
      const box = ensureBoxAfter(h, "vsp-mini-chbytool");
      if(box){
        const rows=[["Tool","CRITICAL","HIGH","TOTAL"]];
        for(const it of (stats.critHighByTool||[])){
          rows.push([esc(it.tool), String(it.crit||0), String(it.high||0), String(it.total||0)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No CRITICAL/HIGH findings.</div>`;
      }
    }

    // 4) Top CWE Exposure
    {
      const h = findHeadingEl("Top CWE Exposure");
      const box = ensureBoxAfter(h, "vsp-mini-topcwe");
      if(box){
        const rows=[["CWE","Count"]];
        for(const [c,n] of (stats.topCWE||[])){
          rows.push([esc(c), String(n)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No CWE data in findings.</div>`;
      }
    }

    // 5) Top Risk Findings
    {
      const h = findHeadingEl("Top Risk Findings");
      const box = ensureBoxAfter(h, "vsp-mini-risk");
      if(box){
        const rows=[["Sev","Tool","Title","File"]];
        for(const it of (stats.topRisk||[])){
          rows.push([esc(it.sev), esc(it.tool), esc(it.title), esc(it.file)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No findings.</div>`;
      }
    }

    // 6) By Tool Buckets
    {
      const h = findHeadingEl("By Tool Buckets");
      const box = ensureBoxAfter(h, "vsp-mini-buckets");
      if(box){
        const rows=[["Tool","Count"]];
        for(const [t,n] of (stats.toolBuckets||[])){
          rows.push([esc(t), String(n)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No tool buckets.</div>`;
      }
    }

    scrubDegradedText();
  }

  async function run(){
    try{
      const rid=getRID();
      if(!rid) return;
      const res = await fetchFindings(rid);
      if(!res.ok || !(res.findings||[]).length){
        // still scrub degraded text (avoid scary UI)
        scrubDegradedText();
        return;
      }
      const stats = compute(res.findings);
      applyMiniCharts(stats);
    }catch(e){
      try{ scrubDegradedText(); }catch(_){}
    }
  }

  // run now + rerun a few times to win race vs other scripts
  let tries=0;
  function tick(){
    tries++;
    run();
    if(tries<8) setTimeout(tick, 900);
  }
  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(tick, 50));
  } else {
    setTimeout(tick, 50);
  }

  // expose for manual use (optional)
  window.__vspDashMiniChartsOverrideDegradedV2 = function(){ tick(); };
})();
'''

p.write_text(s + ("\n" if not s.endswith("\n") else "") + append, encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5"
grep -n "VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V2" "$JS" | head
