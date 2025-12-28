#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_history_center_${TS}" && echo "[BACKUP] $F.bak_history_center_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNS_HISTORY_CENTER_P1_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Add a small toolbar HTML + client-side filtering after table render.
addon = r'''
/* VSP_RUNS_HISTORY_CENTER_P1_V1: search + quick filters (client-side) */
(function(){
  'use strict';

  function _ensureToolbar(){
    const root = document.getElementById("vsp4-runs") || document.querySelector("[data-tab='runs']") || document.body;
    if(!root) return;
    if(document.getElementById("vsp-runs-toolbar")) return;

    const bar = document.createElement("div");
    bar.id="vsp-runs-toolbar";
    bar.style.cssText="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:10px 0 12px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.18);border-radius:14px;background:rgba(2,6,23,.35);";
    bar.innerHTML = `
      <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
        <input id="vsp-runs-q" placeholder="Search RID…" style="width:min(320px,70vw);padding:8px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.22);background:rgba(15,23,42,.45);color:#e2e8f0;font-size:12px;outline:none;">
        <label style="display:inline-flex;gap:6px;align-items:center;font-size:12px;color:#cbd5e1;">
          <input type="checkbox" id="vsp-runs-only-findings"> Has findings
        </label>
        <label style="display:inline-flex;gap:6px;align-items:center;font-size:12px;color:#cbd5e1;">
          <input type="checkbox" id="vsp-runs-only-degraded"> Degraded only
        </label>
        <button id="vsp-runs-reset" style="padding:7px 10px;border-radius:12px;border:1px solid rgba(148,163,184,.22);background:rgba(15,23,42,.55);color:#cbd5e1;font-size:12px;cursor:pointer">Reset</button>
      </div>
      <div style="margin-left:auto;font-size:12px;color:#cbd5e1;opacity:.9">
        <span>Showing: </span><b id="vsp-runs-count">—</b>
      </div>
    `;
    root.prepend(bar);

    const apply = ()=>{ try{ window.__VSP_RUNS_APPLY_FILTER && window.__VSP_RUNS_APPLY_FILTER(); }catch(e){} };
    bar.querySelector("#vsp-runs-q").addEventListener("input", ()=>setTimeout(apply, 80));
    bar.querySelector("#vsp-runs-only-findings").addEventListener("change", apply);
    bar.querySelector("#vsp-runs-only-degraded").addEventListener("change", apply);
    bar.querySelector("#vsp-runs-reset").addEventListener("click", ()=>{
      bar.querySelector("#vsp-runs-q").value="";
      bar.querySelector("#vsp-runs-only-findings").checked=false;
      bar.querySelector("#vsp-runs-only-degraded").checked=false;
      apply();
    });
  }

  // Provide a generic filter function that works on the rendered table rows.
  window.__VSP_RUNS_APPLY_FILTER = function(){
    _ensureToolbar();
    const q = (document.getElementById("vsp-runs-q")?.value || "").trim().toLowerCase();
    const onlyFind = !!document.getElementById("vsp-runs-only-findings")?.checked;
    const onlyDeg = !!document.getElementById("vsp-runs-only-degraded")?.checked;

    // best-effort: find runs table
    const table = document.querySelector("#vsp-runs-table, table[data-vsp-runs], .vsp-runs-table table") || document.querySelector("table");
    if(!table) return;

    const rows = Array.from(table.querySelectorAll("tr")).slice(1);
    let shown = 0;
    for(const tr of rows){
      const txt = (tr.textContent || "").toLowerCase();

      // heuristics:
      const ridOk = !q || txt.includes(q);
      const hasFind = !onlyFind || txt.includes("has_findings") || txt.includes("findings") || txt.includes("true") || txt.includes("total");
      const degOk = !onlyDeg || txt.includes("degraded") || txt.includes("timeout") || txt.includes("rc=");

      const ok = ridOk && hasFind && degOk;
      tr.style.display = ok ? "" : "none";
      if(ok) shown += 1;
    }
    const c = document.getElementById("vsp-runs-count");
    if(c) c.textContent = String(shown);
  };

  // Try install toolbar now and after hashchange
  window.addEventListener("load", ()=>setTimeout(()=>{ _ensureToolbar(); }, 200));
  window.addEventListener("hashchange", ()=>setTimeout(()=>{ _ensureToolbar(); }, 120));
})();
'''

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended history center toolbar")
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null && echo "[OK] node --check OK"
echo "[DONE] patch_runs_history_center_p1_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
