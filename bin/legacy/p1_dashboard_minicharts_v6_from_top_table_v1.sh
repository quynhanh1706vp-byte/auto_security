#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_v6_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_v6_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_DASH_MINICHARTS_V6_FROM_TOP_TABLE_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

append = r'''
/* ===== VSP_P1_DASH_MINICHARTS_V6_FROM_TOP_TABLE_V1 =====
   Fast + correct: compute counts from rendered "Top Findings" table (no extra API).
   Avoid scanning whole DOM / avoid KPI-card parsing.
*/
(function(){
  try{
    if(window.__vspMiniChartsV6_FromTopTable) return;
    window.__vspMiniChartsV6_FromTopTable = true;

    function norm(s){ return (s||"").toString().trim().toUpperCase(); }

    function findSectionHeader(title){
      const want = norm(title);
      // prefer headings only
      const hs = Array.from(document.querySelectorAll("h1,h2,h3,h4,h5,div,span"));
      for(const el of hs){
        const t = norm(el.textContent);
        if(!t) continue;
        if(t === want || t.includes(want)) return el;
      }
      return null;
    }

    function findTopFindingsTable(){
      // Heuristic: find element containing "Top Findings" then locate nearest table under same container
      const hdr = findSectionHeader("Top Findings");
      if(!hdr) return null;

      // walk up to a reasonable container, then search for table
      let root = hdr;
      for(let i=0;i<6 && root;i++){
        const t = (root.textContent||"");
        if(t && t.length > 40) break;
        root = root.parentElement || root;
      }
      // in case that didn't help, just use parent chain
      let container = hdr.parentElement;
      for(let i=0;i<8 && container;i++){
        const tbl = container.querySelector("table");
        if(tbl) return tbl;
        container = container.parentElement;
      }
      // fallback: first table on page
      return document.querySelector("table");
    }

    function readRowsFromTopTable(limit){
      const tbl = findTopFindingsTable();
      if(!tbl) return [];

      const rows = Array.from(tbl.querySelectorAll("tbody tr"));
      if(!rows.length) return [];

      const items = [];
      for(const tr of rows.slice(0, limit)){
        const tds = Array.from(tr.querySelectorAll("td"));
        if(!tds.length) continue;

        // Expect columns: Severity | Title | Tool | (File/Location...)
        const sev = norm(tds[0] ? tds[0].textContent : "");
        const title = (tds[1] ? (tds[1].textContent||"").trim() : "");
        const tool = norm(tds[2] ? tds[2].textContent : "");
        const file = (tds[3] ? (tds[3].textContent||"").trim() : "");

        if(!sev || sev==="NOT LOADED") continue;
        items.push({severity: sev, title, tool: tool||"UNKNOWN", file});
      }
      return items;
    }

    function computeFromItems(items){
      const sevOrder = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const sevCount = Object.create(null);
      for(const s of sevOrder) sevCount[s]=0;

      const toolCount = Object.create(null);
      for(const it of items){
        const s = norm(it.severity);
        if(sevCount[s] === undefined) continue;
        sevCount[s] = (sevCount[s]||0) + 1;
        const t = norm(it.tool) || "UNKNOWN";
        toolCount[t] = (toolCount[t]||0) + 1;
      }
      return {sevCount, toolCount, total: items.length};
    }

    function ensureMiniArea(){
      // Place under "Severity Distribution" section, as a small preformatted block
      const hdr = findSectionHeader("Severity Distribution");
      const host = hdr ? (hdr.parentElement || document.body) : document.body;

      let box = document.getElementById("vsp-mini-v6-box");
      if(box) return box;

      box = document.createElement("div");
      box.id = "vsp-mini-v6-box";
      box.style.cssText = "margin-top:8px; padding:10px 12px; border:1px solid rgba(255,255,255,0.08); border-radius:10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; font-size:12px; color:rgba(255,255,255,0.88); background:rgba(0,0,0,0.18);";
      box.textContent = "MiniCharts V6: waiting...";
      host.appendChild(box);
      return box;
    }

    function renderTextBars(sevCount, total){
      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const box = ensureMiniArea();
      const max = Math.max(1, ...order.map(k => sevCount[k]||0));
      const lines = [];
      lines.push(`RID=${(window.__VSP_RID||"") || (new URL(location.href).searchParams.get("rid")||"")}`);
      lines.push(`TOTAL(top_table_rows)=${total}`);
      for(const k of order){
        const v = sevCount[k]||0;
        const w = Math.round((v/max)*40);
        lines.push(`${k.padEnd(8)} ${String(v).padStart(4)}  ${"█".repeat(w)}`);
      }
      box.textContent = lines.join("\n");
    }

    function renderToolBuckets(toolCount){
      const box = document.getElementById("vsp-mini-v6-tools") || (function(){
        const d = document.createElement("div");
        d.id="vsp-mini-v6-tools";
        d.style.cssText="margin-top:10px; padding:10px 12px; border:1px solid rgba(255,255,255,0.08); border-radius:10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; font-size:12px; color:rgba(255,255,255,0.88); background:rgba(0,0,0,0.18);";
        (document.getElementById("vsp-mini-v6-box")?.parentElement || document.body).appendChild(d);
        return d;
      })();

      const entries = Object.entries(toolCount).sort((a,b)=>b[1]-a[1]).slice(0,10);
      const lines = ["By Tool (top-table)"];
      for(const [k,v] of entries){
        lines.push(`${(k||"UNKNOWN").padEnd(10)} ${String(v).padStart(4)}`);
      }
      box.textContent = lines.join("\n");
    }

    function runOnce(){
      const items = readRowsFromTopTable(400);
      if(items.length < 5) return false;
      const {sevCount, toolCount, total} = computeFromItems(items);
      renderTextBars(sevCount, total);
      renderToolBuckets(toolCount);
      return true;
    }

    // Retry a few times because table may render async
    let tries = 0;
    function tick(){
      tries++;
      if(runOnce()) return;
      if(tries >= 12) {
        ensureMiniArea().textContent = "MiniCharts V6: Top Findings table not ready / not found.";
        return;
      }
      setTimeout(tick, 250);
    }
    setTimeout(tick, 50);
  }catch(e){}
})();
'''
p.write_text(s + "\n" + append + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS" || true; exit 2; }

echo "[DONE] Ctrl+Shift+R: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5?rid=VSP_CI_20251218_114312"
grep -n "VSP_P1_DASH_MINICHARTS_V6_FROM_TOP_TABLE_V1" "$JS" | head -n 1 || true
