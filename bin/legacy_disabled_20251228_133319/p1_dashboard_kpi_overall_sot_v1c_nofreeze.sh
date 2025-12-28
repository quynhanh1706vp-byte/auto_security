#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && NODE_OK=1 || NODE_OK=0
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1"
MARK2="VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1C_NOFREEZE"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_sot_nofreeze_${TS}"
echo "[BACKUP] ${JS}.bak_sot_nofreeze_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

new_block = r'''
/* VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1C_NOFREEZE
   commercial SOT:
   - KPI = run_gate_summary.counts_total (+TOTAL auto)
   - Chip = run_gate_summary.overall
   - NO setInterval 1s; cache DOM once; idle execution; refresh only on RID change
*/
(function(){
  if (window.__VSP_KPI_SOT_NOFREEZE) return;
  window.__VSP_KPI_SOT_NOFREEZE = true;

  const ORIGIN = "";
  const SEVS = ["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
  const cache = new Map(); // sev -> [els]

  const defer = (fn) => {
    try{
      if (window.requestIdleCallback) return requestIdleCallback(fn, { timeout: 1200 });
    }catch(_){}
    return setTimeout(fn, 0);
  };

  function api(path){ return ORIGIN + path; }

  function setText(el, val){
    if(!el) return;
    const t = (val===null || val===undefined || val==="") ? "—" : String(val);
    if(el.textContent !== t) el.textContent = t;
  }

  function uniq(arr){
    const out=[]; const seen=new Set();
    for(const x of arr){ if(x && !seen.has(x)){ seen.add(x); out.push(x); } }
    return out;
  }

  function buildCache(){
    // cache targets once to avoid heavy querySelectorAll loops
    for (const sev of SEVS){
      const s = String(sev).toLowerCase();
      const sels = [
        `[data-kpi="${sev}"]`, `[data-kpi="${s}"]`,
        `[data-sev="${sev}"]`, `[data-sev="${s}"]`,
        `#kpi_${s}`, `#kpi-${s}`,
        `.kpi-${s} .kpi-value`,
        `.kpi[data-sev="${s}"] .kpi-value`,
        `.kpi[data-kpi="${s}"] .kpi-value`
      ];
      let els = [];
      for (const sel of sels){
        try{ document.querySelectorAll(sel).forEach(e=>els.push(e)); }catch(_){}
      }
      cache.set(sev, uniq(els));
    }
  }

  function applyCounts(counts){
    if(!counts || typeof counts !== "object") return;

    let total = 0;
    for(const k of Object.keys(counts)){
      const n = Number(counts[k] ?? 0);
      if(Number.isFinite(n)) total += n;
    }
    const map = Object.assign({}, counts, { TOTAL: total });

    for(const sev of SEVS){
      const val = (map[sev] ?? map[sev.toUpperCase()] ?? map[String(sev).toLowerCase()]);
      const targets = cache.get(sev) || [];
      if(!targets.length) continue;
      for(const el of targets) setText(el, val);
    }
  }

  function setOverallChip(overall){
    const v = String(overall||"").toUpperCase();
    const sels = [
      '[data-overall-chip]','#overallChip','#gateChip','#gateOverall',
      '.gate-chip','.overall-chip','[data-gate="overall"]'
    ];
    let el = null;
    for(const sel of sels){ el = document.querySelector(sel); if(el) break; }
    if(!el) return;

    setText(el, v || "—");
    try{ el.dataset.overall = v; }catch(_){}

    el.classList.remove('is-pass','is-fail','is-warn','vsp-overall-red','vsp-overall-green','vsp-overall-amber');
    if(v === "GREEN" || v === "PASS" || v === "OK") el.classList.add('is-pass','vsp-overall-green');
    else if(v === "RED" || v === "FAIL" || v === "BLOCK") el.classList.add('is-fail','vsp-overall-red');
    else if(v) el.classList.add('is-warn','vsp-overall-amber');
  }

  async function fetchJSON(url, timeoutMs=3500){
    const ac = new AbortController();
    const t = setTimeout(()=>ac.abort(), timeoutMs);
    try{
      const r = await fetch(url, { credentials:"same-origin", cache:"no-store", signal: ac.signal });
      const ct = (r.headers.get("content-type") || "");
      if(!ct.includes("application/json")) throw new Error("non-json content-type=" + ct);
      return await r.json();
    } finally {
      clearTimeout(t);
    }
  }

  function getRid(){
    const qs = new URLSearchParams(location.search);
    return (window.__VSP_RID || window.VSP_RID || qs.get("rid") || localStorage.getItem("vsp_rid") || "");
  }

  let lastRid = "";
  async function refresh(){
    let rid = getRid();
    if(!rid){
      try{
        const j = await fetchJSON(api("/api/vsp/rid_latest"));
        rid = (j && j.rid) ? String(j.rid) : "";
      }catch(_){}
    }
    if(!rid) return;

    if (rid === lastRid) return;
    lastRid = rid;
    try{ localStorage.setItem("vsp_rid", rid); }catch(_){}

    try{
      const j = await fetchJSON(api("/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json"));
      setOverallChip(j.overall || "");
      applyCounts(j.counts_total || null);
    }catch(_){}
  }

  function boot(){
    buildCache();
    defer(()=>refresh());
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();

  // refresh only when RID might change
  window.addEventListener("vsp:ridchange", ()=>defer(()=>refresh()));
  window.addEventListener("storage", (e)=>{ if(e && e.key==="vsp_rid") defer(()=>refresh()); });
})();
 /* /VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1C_NOFREEZE */
'''

# Replace old block (v1) if exists
if "VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1C_NOFREEZE" in s:
    print("[OK] already patched: V1C_NOFREEZE")
else:
    # Remove previous V1 block if present (both marker styles)
    patterns = [
        r"/\*\s*VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1.*?\*/.*?/\*\s*/VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1\s*\*/",
        r"/\*\s*VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1.*?\*/.*?/\*\s*/\s*VSP_P1_DASHBOARD_KPI_OVERALL_SOT_V1\s*\*/",
    ]
    for pat in patterns:
        s2, n = re.subn(pat, "", s, flags=re.S)
        if n:
            s = s2
            print("[OK] removed old V1 block, n=", n)
            break

    s = s.rstrip() + "\n\n" + new_block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] patched: V1C_NOFREEZE")
PY

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] applied NO-FREEZE KPI/overall SOT patch."
