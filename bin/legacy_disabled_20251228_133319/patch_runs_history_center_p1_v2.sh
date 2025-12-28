#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_history_center_v2_${TS}" && echo "[BACKUP] $F.bak_history_center_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNS_HISTORY_CENTER_P1_V2"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

addon = r'''
/* VSP_RUNS_HISTORY_CENTER_P1_V2: toolbar filters + client-side filtering + refetch */
(function(){
  'use strict';

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function normRid(x){
    if(!x) return "";
    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');
  }

  function getPanel(){
    // best-effort: find runs main pane
    return document.getElementById("vsp-runs-main")
        || document.querySelector("#vsp-runs-pane")
        || document.querySelector("[data-tab='runs']")
        || document.body;
  }

  function ensureToolbar(){
    const host = getPanel();
    if(!host) return null;
    if(document.getElementById("vsp-runs-history-toolbar")) return document.getElementById("vsp-runs-history-toolbar");

    const bar = document.createElement("div");
    bar.id = "vsp-runs-history-toolbar";
    bar.style.cssText = "display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between;margin:10px 0 12px;padding:10px;border-radius:14px;border:1px solid rgba(148,163,184,.18);background:rgba(2,6,23,.35);";

    bar.innerHTML = `
      <div style="display:flex;flex-wrap:wrap;gap:10px;align-items:center;">
        <input id="vsp-runs-q" placeholder="Search RID contains…" style="width:240px;max-width:45vw;padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.35);color:#e2e8f0;">
        <label style="display:flex;gap:8px;align-items:center;font-size:12px;color:#cbd5e1;">
          <input id="vsp-runs-hasfind" type="checkbox"> Has findings
        </label>
        <label style="display:flex;gap:8px;align-items:center;font-size:12px;color:#cbd5e1;">
          <input id="vsp-runs-degraded" type="checkbox"> Degraded only
        </label>
        <select id="vsp-runs-limit" style="padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.35);color:#e2e8f0;">
          <option value="20">limit=20</option>
          <option value="50" selected>limit=50</option>
          <option value="100">limit=100</option>
          <option value="200">limit=200</option>
        </select>
      </div>
      <div style="display:flex;gap:10px;align-items:center;">
        <span id="vsp-runs-count" style="font-size:12px;color:#94a3b8;">…</span>
        <button id="vsp-runs-apply" style="padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.55);color:#e2e8f0;cursor:pointer;">Apply</button>
        <button id="vsp-runs-refresh" style="padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.55);color:#e2e8f0;cursor:pointer;">Refresh</button>
        <button id="vsp-runs-clear" style="padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.25);background:rgba(2,6,23,.55);color:#e2e8f0;cursor:pointer;">Clear</button>
      </div>
    `;

    // insert at top of runs panel
    host.insertBefore(bar, host.firstChild);
    return bar;
  }

  function getRows(){
    // rows marked by data-rid/data-run-id or buttons containing Use RID
    const rows = qsa("[data-rid],[data-run-id],tr[data-rid],tr[data-run-id]");
    if(rows.length) return rows;

    // fallback: find table rows in runs pane
    const host = getPanel();
    return qsa("tr", host).filter(tr => tr.innerText && tr.innerText.includes("VSP_CI_"));
  }

  function rowRid(row){
    const rid = normRid(row.getAttribute("data-rid") || row.getAttribute("data-run-id") || "");
    if(rid) return rid;
    // fallback: parse from text
    const t = (row.innerText||"");
    const m = t.match(/VSP_CI_\d{8}_\d{6}/);
    return m ? m[0] : "";
  }

  function rowHasFindings(row){
    const t=(row.innerText||"").toLowerCase();
    // heuristic: total>0 or "findings" badge; you may adjust later
    return t.includes("total") or False
  }

  function rowDegraded(row){
    const t=(row.innerText||"").toLowerCase();
    return t.includes("degrad") || t.includes("timeout") || t.includes("failed");
  }

  function applyFilter(){
    const q = (qs("#vsp-runs-q")||{}).value || "";
    const hasFind = !!(qs("#vsp-runs-hasfind")||{}).checked;
    const degr = !!(qs("#vsp-runs-degraded")||{}).checked;

    let shown=0, total=0;
    for(const r of getRows()){
      total++;
      const rid = rowRid(r);
      let ok = true;
      if(q && rid && !rid.toLowerCase().includes(q.toLowerCase())) ok = false;
      if(q && !rid) ok = false;

      // simple heuristics: we hide nothing if signals absent
      if(hasFind){
        // try to detect total findings number in row text
        const t = (r.innerText||"");
        const m = t.match(/\btotal\b\s*[:=]?\s*(\d+)/i) || t.match(/\bfindings\b\s*[:=]?\s*(\d+)/i);
        const n = m ? parseInt(m[1]||"0",10) : 0;
        if(!(n>0)) ok = false;
      }
      if(degr){
        if(!rowDegraded(r)) ok = false;
      }

      r.style.display = ok ? "" : "none";
      if(ok) shown++;
    }
    const el = qs("#vsp-runs-count");
    if(el) el.textContent = `Showing ${shown}/${total}`;
  }

  async function refreshFromApi(){
    const limit = parseInt((qs("#vsp-runs-limit")||{}).value || "50", 10);
    // try to call existing global loader if present
    try{
      if(window.VSP_RUNS && typeof window.VSP_RUNS.load==="function"){
        await window.VSP_RUNS.load({limit});
        applyFilter();
        return;
      }
    }catch(e){}

    // fallback: reload page hash runs
    console.info("[VSP_RUNS_HISTORY_CENTER] fallback reload");
    location.reload();
  }

  function clearAll(){
    const q=qs("#vsp-runs-q"); if(q) q.value="";
    const a=qs("#vsp-runs-hasfind"); if(a) a.checked=false;
    const b=qs("#vsp-runs-degraded"); if(b) b.checked=false;
    applyFilter();
  }

  function boot(){
    const bar = ensureToolbar();
    if(!bar) return;

    bar.querySelector("#vsp-runs-apply")?.addEventListener("click", applyFilter);
    bar.querySelector("#vsp-runs-clear")?.addEventListener("click", clearAll);
    bar.querySelector("#vsp-runs-refresh")?.addEventListener("click", refreshFromApi);

    bar.querySelector("#vsp-runs-q")?.addEventListener("keydown", (e)=>{ if(e.key==="Enter") applyFilter(); });

    // initial
    setTimeout(applyFilter, 800);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
'''
s = s.rstrip() + "\n\n" + MARK + "\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended runs history center v2")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_runs_history_center_p1_v2"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
