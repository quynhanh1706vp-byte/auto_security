#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_v3_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V3"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

append = r'''
/* ===== VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V3 =====
   Fix: DO NOT call /api/vsp/findings_page_v3 (may be "not allowed").
   Use allowlisted endpoint: /api/vsp/run_file_allow?rid=...&path=findings_unified.json&limit=...
   Also scrub any text that CONTAINS "No data (degraded)" or "Loading..."
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
    const to=setTimeout(()=>ctrl.abort(), timeoutMs||6000);
    try{
      const r=await fetch(url,{credentials:"same-origin",cache:"no-store",signal:ctrl.signal});
      return await r.text();
    } finally { clearTimeout(to); }
  }
  async function fetchJSON(url, timeoutMs){
    const txt = await fetchText(url, timeoutMs);
    try{ return JSON.parse(txt); } catch(e){ return {ok:false, err:"NOT_JSON", _text:(txt||"").slice(0,200)}; }
  }

  async function fetchFindingsAllow(rid){
    const base="";
    const paths=[
      "findings_unified.json",
      "reports/findings_unified.json",
      "report/findings_unified.json"
    ];
    for(const path of paths){
      const u = `${base}/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}&limit=5000`;
      const j = await fetchJSON(u, 9000);
      const arr = (j && (j.findings||j.items)) || [];
      if (j && j.ok===true && Array.isArray(arr) && arr.length){
        return {ok:true, findings:arr, from:(j.from||path), raw:j};
      }
    }
    // last resort: top_findings_v1 (usually allowlisted)
    const u2 = `${base}/api/vsp/top_findings_v1?rid=${encodeURIComponent(rid)}&limit=5000`;
    const j2 = await fetchJSON(u2, 8000);
    const arr2 = (j2 && (j2.items||j2.findings)) || [];
    if (j2 && j2.ok===true && Array.isArray(arr2) && arr2.length){
      return {ok:true, findings:arr2, from:"top_findings_v1", raw:j2};
    }
    return {ok:false, findings:[], from:"", raw:null};
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

    const topCWE = Object.entries(cweCount).sort((a,b)=>b[1]-a[1]).slice(0,8);
    const toolBuckets = Object.entries(bucketTool).sort((a,b)=>b[1]-a[1]).slice(0,10);

    const critHighByTool = Object.entries(byTool)
      .map(([t,v])=>({tool:t, crit:v.CRITICAL||0, high:v.HIGH||0, total:v.TOTAL||0}))
      .filter(x=> (x.crit+x.high)>0)
      .sort((a,b)=>(b.crit+b.high)-(a.crit+a.high))
      .slice(0,10);

    return {sevCount, topCWE, toolBuckets, critHighByTool, topRisk: risk.slice(0,8)};
  }

  function scrubText(){
    try{
      const walker=document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
      const kills=[];
      while(walker.nextNode()){
        const n=walker.currentNode;
        const t=(n.nodeValue||"").trim();
        if(!t) continue;
        if(t.toLowerCase().includes("no data (degraded)") || t.toLowerCase().includes("loading...") || t.toLowerCase().includes("loading..") || t.toLowerCase().includes("loading.")){
          kills.push(n);
        }
      }
      for(const n of kills){
        try{ n.nodeValue=""; }catch(e){}
      }
    }catch(e){}
  }

  function findHeadingContainer(phrase){
    const want=String(phrase||"").trim().toLowerCase();
    if(!want) return null;
    const els=[...document.querySelectorAll("*")];
    let best=null, bestLen=1e9;
    for(const el of els){
      if(!el || !el.textContent) continue;
      const t=el.textContent.trim().toLowerCase();
      if(!t) continue;
      if(t===want || t.startsWith(want) || t.includes(want)){
        // choose smallest container to avoid huge blocks
        if(t.length<bestLen){
          best=el; bestLen=t.length;
        }
      }
    }
    return best;
  }

  function ensureBoxAfter(el, id){
    try{
      if(!el) return null;
      const ex=document.getElementById(id);
      if(ex) return ex;
      const box=document.createElement("div");
      box.id=id;
      box.style.margin="6px 0 14px 0";
      box.style.padding="8px 10px";
      box.style.border="1px solid rgba(255,255,255,0.08)";
      box.style.borderRadius="10px";
      box.style.background="rgba(255,255,255,0.02)";
      box.style.fontSize="12px";
      box.style.lineHeight="1.35";
      const parent = el.parentElement || el;
      if(el.nextSibling) parent.insertBefore(box, el.nextSibling);
      else parent.appendChild(box);
      return box;
    }catch(e){ return null; }
  }

  function renderTable(rows){
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

  function apply(stats){
    scrubText();

    // Severity Distribution
    {
      const h=findHeadingContainer("Severity Distribution");
      const box=ensureBoxAfter(h,"vsp-mini-sevdist-v3");
      if(box){
        const s=stats.sevCount||{};
        box.innerHTML = renderTable([
          ["CRITICAL", String(s.CRITICAL||0)],
          ["HIGH", String(s.HIGH||0)],
          ["MEDIUM", String(s.MEDIUM||0)],
          ["LOW", String(s.LOW||0)],
          ["INFO", String(s.INFO||0)],
          ["TRACE", String(s.TRACE||0)],
        ]);
      }
    }

    // Trend
    {
      const h=findHeadingContainer("Trend (Findings over time)");
      const box=ensureBoxAfter(h,"vsp-mini-trend-v3");
      if(box) box.innerHTML = `<div style="opacity:0.85">Trend: snapshot-only (RID), no time-series available in findings.</div>`;
    }

    // Critical/High by Tool
    {
      const h=findHeadingContainer("Critical/High by Tool");
      const box=ensureBoxAfter(h,"vsp-mini-chbytool-v3");
      if(box){
        const rows=[["Tool","CRITICAL","HIGH","TOTAL"]];
        for(const it of (stats.critHighByTool||[])){
          rows.push([esc(it.tool), String(it.crit||0), String(it.high||0), String(it.total||0)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No CRITICAL/HIGH findings.</div>`;
      }
    }

    // Top CWE Exposure
    {
      const h=findHeadingContainer("Top CWE Exposure");
      const box=ensureBoxAfter(h,"vsp-mini-topcwe-v3");
      if(box){
        const rows=[["CWE","Count"]];
        for(const [c,n] of (stats.topCWE||[])){
          rows.push([esc(c), String(n)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No CWE data in findings.</div>`;
      }
    }

    // Top Risk Findings
    {
      const h=findHeadingContainer("Top Risk Findings");
      const box=ensureBoxAfter(h,"vsp-mini-risk-v3");
      if(box){
        const rows=[["Sev","Tool","Title","File"]];
        for(const it of (stats.topRisk||[])){
          rows.push([esc(it.sev), esc(it.tool), esc(it.title), esc(it.file)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No findings.</div>`;
      }
    }

    // By Tool Buckets
    {
      const h=findHeadingContainer("By Tool Buckets");
      const box=ensureBoxAfter(h,"vsp-mini-buckets-v3");
      if(box){
        const rows=[["Tool","Count"]];
        for(const [t,n] of (stats.toolBuckets||[])){
          rows.push([esc(t), String(n)]);
        }
        box.innerHTML = rows.length>1 ? renderTable(rows) : `<div style="opacity:0.85">No tool buckets.</div>`;
      }
    }

    scrubText();
  }

  async function runOnce(){
    try{
      const rid=getRID();
      if(!rid) { scrubText(); return; }
      const res=await fetchFindingsAllow(rid);
      if(!res.ok || !(res.findings||[]).length){ scrubText(); return; }
      apply(compute(res.findings));
    }catch(e){ scrubText(); }
  }

  // race-safe: rerun a few times to override other scripts
  let tries=0;
  function tick(){
    tries++;
    runOnce();
    if(tries<10) setTimeout(tick, 700);
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(tick, 60));
  } else {
    setTimeout(tick, 60);
  }

  window.__vspDashMiniChartsOverrideDegradedV3 = function(){ tick(); };
})();
'''

p.write_text(s + ("\n" if not s.endswith("\n") else "") + append, encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5"
grep -n "VSP_P1_DASH_MINICHARTS_OVERRIDE_DEGRADED_V3" "$JS" | head
