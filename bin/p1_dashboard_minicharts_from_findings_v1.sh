#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_FROM_FINDINGS_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

patch = r"""
/* ===== VSP_P1_DASH_MINICHARTS_FROM_FINDINGS_V1 =====
   Purpose: eliminate stuck Loading/No data placeholders on /vsp5 by deriving stats from findings_page_v3.
   Safe: no infinite loops, single-shot, timeout fetch, only touches known section labels if placeholders still present.
*/
(function(){
  try{
    if(!location || !/\/vsp5\b/.test(String(location.pathname||""))) return;
    const ONCE="__vspMiniChartsFromFindingsOnce";
    if(window[ONCE]) return;
    window[ONCE]=true;

    function getRID(){
      try{
        const u=new URL(location.href);
        const rid=u.searchParams.get("rid");
        if(rid) return rid;
      }catch(e){}
      // try common globals
      if(window.__VSP_RID) return String(window.__VSP_RID);
      if(window.__rid) return String(window.__rid);
      // try stamp text: "RID: XXX"
      const t=(document.body && document.body.innerText) ? document.body.innerText : "";
      const m=t.match(/\bRID:\s*([A-Za-z0-9_:-]{6,})\b/);
      return m ? m[1] : "";
    }

    async function fetchJson(url, timeoutMs){
      const ctrl=new AbortController();
      const to=setTimeout(()=>{ try{ ctrl.abort(); }catch(e){} }, Math.max(800, timeoutMs|0));
      try{
        const r=await fetch(url, {signal: ctrl.signal, credentials:"same-origin"});
        const txt=await r.text();
        try{ return JSON.parse(txt); }catch(e){ return {ok:false, err:"not_json", status:r.status, head: String(txt||"").slice(0,200)}; }
      }catch(e){
        return {ok:false, err:"fetch_failed", msg:String(e||"")};
      }finally{
        try{ clearTimeout(to); }catch(e){}
      }
    }

    function normItems(j){
      if(!j) return [];
      if(Array.isArray(j.items)) return j.items;
      if(Array.isArray(j.findings)) return j.findings;
      if(j.data && Array.isArray(j.data.items)) return j.data.items;
      return [];
    }

    function countBy(items, keyFn){
      const m=new Map();
      for(const it of items){
        const k=keyFn(it);
        if(!k) continue;
        m.set(k, (m.get(k)||0)+1);
      }
      return m;
    }

    function topN(map, n){
      const arr=[...map.entries()].sort((a,b)=> (b[1]-a[1]) || String(a[0]).localeCompare(String(b[0])));
      return arr.slice(0, n);
    }

    function findLabelEl(label){
      // find an element whose trimmed text starts with label
      const all = document.querySelectorAll("div,span,h1,h2,h3,h4,h5,section");
      label=String(label||"").trim();
      for(const el of all){
        const tx=(el.textContent||"").trim();
        if(tx === label) return el;
      }
      // fallback: contains
      for(const el of all){
        const tx=(el.textContent||"").trim();
        if(tx.startsWith(label)) return el;
      }
      return null;
    }

    function sectionLooksPlaceholder(container){
      if(!container) return true;
      const tx=(container.textContent||"").toLowerCase();
      return tx.includes("loading") || tx.includes("no data") || tx.includes("degraded");
    }

    function renderUnderLabel(label, lines){
      const lab=findLabelEl(label);
      if(!lab) return false;

      // choose a container near label
      let box = lab.parentElement;
      if(!box) return false;

      // if placeholder was scrubbed somewhere deeper, still override only when placeholder-like
      if(!sectionLooksPlaceholder(box)){
        // sometimes placeholder is in next siblings
        let sib=lab.nextElementSibling;
        if(sib && sectionLooksPlaceholder(sib)) box=sib;
        else return false;
      }

      const pre=document.createElement("pre");
      pre.style.margin="6px 0 0 0";
      pre.style.padding="8px 10px";
      pre.style.borderRadius="10px";
      pre.style.background="rgba(255,255,255,0.03)";
      pre.style.border="1px solid rgba(255,255,255,0.06)";
      pre.style.fontSize="12px";
      pre.style.lineHeight="1.35";
      pre.style.whiteSpace="pre-wrap";
      pre.textContent=lines.join("\n");

      // keep the label itself, replace rest
      // safest: remove siblings after label within same parent
      try{
        const parent=lab.parentElement;
        if(parent){
          // remove any existing placeholder-like nodes under same parent (except label)
          const kids=[...parent.children];
          for(const k of kids){
            if(k===lab) continue;
            const t=(k.textContent||"").toLowerCase();
            if(t.includes("loading") || t.includes("no data") || t.includes("degraded")){
              try{ k.remove(); }catch(e){}
            }
          }
          parent.appendChild(pre);
          return true;
        }
      }catch(e){}
      try{
        box.appendChild(pre);
        return true;
      }catch(e){}
      return false;
    }

    async function run(){
      const rid=getRID();
      if(!rid) return;

      const url = "/api/vsp/findings_page_v3?rid="+encodeURIComponent(rid)+"&limit=2000&offset=0";
      const j = await fetchJson(url, 9000);
      const items = normItems(j);

      if(!(j && j.ok===true) || !items.length){
        // still try to erase placeholders gently
        renderUnderLabel("Severity Distribution", ["No data (API missing or empty).", "Hint: /api/vsp/findings_page_v3 must return ok:true and items[]."]);
        renderUnderLabel("Top CWE Exposure", ["No data."]);
        renderUnderLabel("Critical/High by Tool", ["No data."]);
        renderUnderLabel("Top Risk Findings", ["No data."]);
        renderUnderLabel("By Tool Buckets", ["No data."]);
        renderUnderLabel("Trend (Findings over time)", ["No trend data (needs history API)."]);
        return;
      }

      const sev = countBy(items, it => String(it.severity||"").toUpperCase());
      const tool = countBy(items, it => String(it.tool||"").toLowerCase());
      const cwe = countBy(items, it => {
        const v = it.cwe;
        if(v===null || v===undefined) return "";
        const s = String(v).trim();
        if(!s) return "";
        return s.startsWith("CWE-") ? s : ("CWE-"+s);
      });

      // critical/high by tool
      const chByTool = new Map();
      for(const it of items){
        const s=String(it.severity||"").toUpperCase();
        if(s!=="CRITICAL" and s!=="HIGH") continue;
        const t=String(it.tool||"").toLowerCase()||"unknown";
        chByTool.set(t, (chByTool.get(t)||0)+1);
      }

      // top risk findings (pick CRITICAL/HIGH first)
      const rank = {"CRITICAL": 5, "HIGH":4, "MEDIUM":3, "LOW":2, "INFO":1, "TRACE":0};
      const top = items.slice().sort((a,b)=>{
        const ra=rank[String(a.severity||"").toUpperCase()] ?? -1
        const rb=rank[String(b.severity||"").toUpperCase()] ?? -1
        if(rb!==ra) return rb-ra;
        return String(a.title||"").localeCompare(String(b.title||""));
      }).slice(0, 8);

      // buckets by tool (all severities)
      const toolTop = topN(tool, 12);

      renderUnderLabel("Severity Distribution", [
        `RID=${rid}`,
        `TOTAL(items sample)= ${items.length}`,
        ...topN(sev, 20).map(([k,v])=> `${k.padEnd(8)} ${v}`)
      ]);

      renderUnderLabel("Critical/High by Tool", [
        ...topN(chByTool, 20).map(([k,v])=> `${String(k).padEnd(12)} ${v}`)
      ]);

      renderUnderLabel("Top CWE Exposure", [
        ...topN(cwe, 15).map(([k,v])=> `${String(k).padEnd(10)} ${v}`),
        cwe.size ? "" : "(no CWE field in items)"
      ]);

      renderUnderLabel("Top Risk Findings", top.map(it=>{
        const s=String(it.severity||"").toUpperCase();
        const t=String(it.tool||"").toLowerCase();
        const title=String(it.title||"").slice(0,120);
        return `${s.padEnd(8)} ${t.padEnd(10)} ${title}`;
      }));

      renderUnderLabel("By Tool Buckets", toolTop.map(([k,v])=> `${String(k).padEnd(12)} ${v}`));

      renderUnderLabel("Trend (Findings over time)", [
        "No trend data (single-run view).",
        "To enable: implement /api/vsp/trend_v1 backed by runs history."
      ]);
    }

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  }catch(e){}
})();
"""
s2 = s + ("\n" if not s.endswith("\n") else "") + patch + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Hard refresh: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5 (Ctrl+Shift+R)"
echo "[CHECK] marker:"
grep -n "VSP_P1_DASH_MINICHARTS_FROM_FINDINGS_V1" -n "$JS" | head
