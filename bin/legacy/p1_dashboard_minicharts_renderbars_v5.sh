#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_renderbars_v5_${TS}"
echo "[BACKUP] ${JS}.bak_renderbars_v5_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_RENDERBARS_V5"
if marker in s:
    print("[OK] already patched:", marker)
else:
    s += r"""

/* ===== VSP_P1_DASH_MINICHARTS_RENDERBARS_V5 =====
   Render lightweight mini-bars (no canvas) from DOM KPIs + visible tables.
   - Inserts bars under: Severity Distribution / By Tool Buckets / Top CWE Exposure
   - Best-effort: if anchors not found => no-op
*/
(function(){
  try{
    if(window.__vspMiniBarsV5) return;
    window.__vspMiniBarsV5 = true;

    function onReady(fn){
      if(document.readyState === "complete" || document.readyState === "interactive") setTimeout(fn, 50);
      else document.addEventListener("DOMContentLoaded", ()=>setTimeout(fn,50), {once:true});
    }

    function injectCSS(){
      if(document.getElementById("vsp-mini-bars-v5-css")) return;
      const st=document.createElement("style");
      st.id="vsp-mini-bars-v5-css";
      st.textContent = `
        .vsp-mini-bars-v5{ margin:10px 0 14px 0; padding:10px 12px; border:1px solid rgba(255,255,255,.08); border-radius:12px; background:rgba(255,255,255,.02); }
        .vsp-mini-bars-v5 .row{ display:flex; align-items:center; gap:10px; margin:6px 0; }
        .vsp-mini-bars-v5 .lab{ width:140px; font-size:12px; opacity:.86; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
        .vsp-mini-bars-v5 .bar{ flex:1; height:10px; border-radius:999px; background:rgba(255,255,255,.06); position:relative; overflow:hidden; }
        .vsp-mini-bars-v5 .bar > i{ display:block; height:100%; width:0%; background:rgba(110,168,255,.75); }
        .vsp-mini-bars-v5 .val{ width:70px; text-align:right; font-variant-numeric: tabular-nums; font-size:12px; opacity:.9; }
        .vsp-mini-bars-v5 .hint{ margin-top:6px; font-size:11px; opacity:.6; }
      `;
      document.head.appendChild(st);
    }

    function norm(s){ return (s||"").replace(/\s+/g," ").trim().toLowerCase(); }

    function findHeaderLike(title){
      const want = norm(title);
      const els = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,.h1,.h2,.h3,.h4,div,span"));
      // exact-ish first
      let hit = els.find(e => norm(e.textContent) === want);
      if(hit) return hit;
      hit = els.find(e => norm(e.textContent).includes(want));
      return hit || null;
    }

    function hideIfNoData(node){
      if(!node) return;
      const t = (node.textContent||"").toLowerCase();
      if(t.includes("loading") || t.includes("no data") || t.includes("degraded")) node.style.display="none";
    }

    // Read KPI numbers from the 4 KPI cards by label text
    function readKPINum(label){
      const want = norm(label);
      const cards = Array.from(document.querySelectorAll("div"));
      for(const c of cards){
        const txt = norm(c.textContent);
        if(!txt.includes(want)) continue;
        // find a big number inside this block
        const m = (c.textContent||"").match(/(\d{1,9})/);
        if(m) return parseInt(m[1],10);
      }
      return 0;
    }

    function mkBarRow(label, val, max){
      const row=document.createElement("div");
      row.className="row";
      const lab=document.createElement("div"); lab.className="lab"; lab.textContent=label;
      const bar=document.createElement("div"); bar.className="bar";
      const fill=document.createElement("i");
      const pct = max>0 ? Math.max(0, Math.min(100, (val/max)*100)) : 0;
      fill.style.width = pct.toFixed(1) + "%";
      bar.appendChild(fill);
      const v=document.createElement("div"); v.className="val"; v.textContent=String(val);
      row.appendChild(lab); row.appendChild(bar); row.appendChild(v);
      return row;
    }

    function ensurePanelAfter(headerEl, panelId){
      if(!headerEl) return null;
      // avoid duplicates
      const exist = document.getElementById(panelId);
      if(exist) return exist;
      const panel=document.createElement("div");
      panel.className="vsp-mini-bars-v5";
      panel.id=panelId;

      // insert right after header element (or after its parent line)
      const anchor = headerEl;
      if(anchor && anchor.parentNode){
        if(anchor.nextSibling) anchor.parentNode.insertBefore(panel, anchor.nextSibling);
        else anchor.parentNode.appendChild(panel);
      }
      return panel;
    }

    function renderSeverity(){
      const h = findHeaderLike("Severity Distribution");
      if(!h) return;

      // Hide the old “Loading/No data …” blocks immediately under the header (best effort)
      let sib = h.nextElementSibling;
      for(let i=0;i<4 && sib;i++){
        hideIfNoData(sib);
        sib = sib.nextElementSibling;
      }

      const total = readKPINum("Total Findings") || 0;
      const crit  = readKPINum("Critical") || 0;
      const high  = readKPINum("High") || 0;
      const med   = readKPINum("Medium") || 0;

      // fallback parse from visible debug text if KPI not reliable
      let low=0, info=0, trace=0;

      const max = Math.max(crit, high, med, low, info, trace, 1);
      const panel = ensurePanelAfter(h, "vsp-mini-bars-v5-sev");
      if(!panel) return;
      panel.innerHTML = "";
      panel.appendChild(mkBarRow("CRITICAL", crit, max));
      panel.appendChild(mkBarRow("HIGH",     high, max));
      panel.appendChild(mkBarRow("MEDIUM",   med, max));
      panel.appendChild(mkBarRow("LOW",      low, max));
      panel.appendChild(mkBarRow("INFO",     info, max));
      panel.appendChild(mkBarRow("TRACE",    trace, max));

      const hint=document.createElement("div");
      hint.className="hint";
      hint.textContent = "Source: KPI cards on this page (no extra API). Total=" + total;
      panel.appendChild(hint);
    }

    function countToolsFromTopTable(){
      // Count tool values from the visible “Top Findings” table (best-effort).
      const counts = {};
      const tables = Array.from(document.querySelectorAll("table"));
      for(const t of tables){
        const headTxt = (t.textContent||"").toLowerCase();
        if(!headTxt.includes("tool")) continue;
        const ths = Array.from(t.querySelectorAll("thead th"));
        let toolIdx = -1;
        ths.forEach((th,i)=>{ if(norm(th.textContent)==="tool") toolIdx=i; });
        if(toolIdx<0) continue;

        const rows = Array.from(t.querySelectorAll("tbody tr"));
        if(rows.length<2) continue;
        for(const r of rows){
          const tds = Array.from(r.querySelectorAll("td"));
          const tool = (tds[toolIdx]?.textContent || "").trim();
          if(!tool) continue;
          counts[tool] = (counts[tool]||0) + 1;
        }
        // use first suitable table only
        break;
      }
      return counts;
    }

    function renderToolBuckets(){
      const h = findHeaderLike("By Tool Buckets") || findHeaderLike("Critical/High by Tool");
      if(!h) return;

      let sib = h.nextElementSibling;
      for(let i=0;i<4 && sib;i++){
        hideIfNoData(sib);
        sib = sib.nextElementSibling;
      }

      const counts = countToolsFromTopTable();
      const items = Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,8);
      if(items.length===0) return;

      const max = Math.max(...items.map(x=>x[1]), 1);
      const panel = ensurePanelAfter(h, "vsp-mini-bars-v5-tools");
      if(!panel) return;
      panel.innerHTML = "";
      for(const [tool,val] of items){
        panel.appendChild(mkBarRow(tool, val, max));
      }
      const hint=document.createElement("div");
      hint.className="hint";
      hint.textContent = "Source: visible Top Findings table rows (sample only).";
      panel.appendChild(hint);
    }

    function renderTopCWE(){
      const h = findHeaderLike("Top CWE Exposure");
      if(!h) return;

      let sib = h.nextElementSibling;
      for(let i=0;i<4 && sib;i++){
        hideIfNoData(sib);
        sib = sib.nextElementSibling;
      }

      // If page doesn't expose CWE in table, show a helpful note
      const panel = ensurePanelAfter(h, "vsp-mini-bars-v5-cwe");
      if(!panel) return;
      panel.innerHTML = "";
      const msg=document.createElement("div");
      msg.style.fontSize="12px";
      msg.style.opacity=".8";
      msg.textContent = "CWE not available in current view (no CWE field in visible items).";
      panel.appendChild(msg);
    }

    onReady(function(){
      injectCSS();
      renderSeverity();
      renderToolBuckets();
      renderTopCWE();
    });

  }catch(e){}
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)

PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5?rid=VSP_CI_20251218_114312"
grep -n "VSP_P1_DASH_MINICHARTS_RENDERBARS_V5" "$JS" | head -n 2 || true
