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

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kpi_overall_${TS}"
echo "[BACKUP] ${JS}.bak_kpi_overall_${TS}"

python3 - <<PY
from pathlib import Path
import re

p = Path("$JS")
s = p.read_text(encoding="utf-8", errors="replace")

if "$MARK" in s:
    print("[OK] already patched:", "$MARK")
else:
    inject = r'''
/* ''' + "$MARK" + r''' (commercial SOT: KPI=run_gate_summary.counts_total, chip=run_gate_summary.overall) */
(function(){
  const ORIGIN = ""; // same-origin
  const SEVS = ["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function api(path){ return ORIGIN + path; }

  function uniq(arr){
    const out=[]; const seen=new Set();
    for(const x of arr){ if(x && !seen.has(x)){ seen.add(x); out.push(x); } }
    return out;
  }

  function setText(el, val){
    if(!el) return;
    const t = (val===null || val===undefined || val==="") ? "—" : String(val);
    if(el.textContent !== t) el.textContent = t;
  }

  function findKpiTargets(sev){
    const s = String(sev).toLowerCase();
    const sels = [
      `[data-kpi="${sev}"]`, `[data-kpi="${s}"]`,
      `[data-sev="${sev}"]`, `[data-sev="${s}"]`,
      `#kpi_${s}`, `#kpi-${s}`, `#kpi${sev}`, `#kpi${sev[0] + s.slice(1)}`,
      `.kpi-${s} .kpi-value`, `.kpi[data-sev="${s}"] .kpi-value`, `.kpi[data-kpi="${s}"] .kpi-value`
    ];
    let out=[];
    for(const sel of sels){
      try{ document.querySelectorAll(sel).forEach(e=>out.push(e)); }catch(_){}
    }
    return uniq(out);
  }

  function setOverallChip(overall){
    const sels = [
      '[data-overall-chip]','#overallChip','#gateChip','#gateOverall',
      '.gate-chip','.overall-chip','[data-gate="overall"]'
    ];
    let el = null;
    for(const sel of sels){ el = document.querySelector(sel); if(el) break; }
    if(!el) return;

    const v = String(overall||"").toUpperCase();
    setText(el, v || "—");
    try{ el.dataset.overall = v; }catch(_){}

    // normalize classes but avoid breaking existing CSS
    el.classList.remove('is-pass','is-fail','is-warn','vsp-overall-red','vsp-overall-green','vsp-overall-amber');
    if(v === "GREEN" || v === "PASS" || v === "OK") el.classList.add('is-pass','vsp-overall-green');
    else if(v === "RED" || v === "FAIL" || v === "BLOCK") el.classList.add('is-fail','vsp-overall-red');
    else if(v) el.classList.add('is-warn','vsp-overall-amber');
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
      const targets = findKpiTargets(sev);
      if(!targets.length) continue;
      targets.forEach(el => setText(el, val));
    }
  }

  async function fetchJSON(url){
    const r = await fetch(url, { credentials: "same-origin", cache: "no-store" });
    const ct = (r.headers.get("content-type") || "");
    if(!ct.includes("application/json")) throw new Error("non-json content-type=" + ct);
    return await r.json();
  }

  function getRid(){
    const qs = new URLSearchParams(location.search);
    return (window.__VSP_RID || window.VSP_RID || qs.get("rid") || localStorage.getItem("vsp_rid") || "");
  }

  async function loadGateSummary(){
    let rid = getRid();
    if(!rid){
      try{
        const j = await fetchJSON(api("/api/vsp/rid_latest"));
        rid = (j && j.rid) ? String(j.rid) : "";
      }catch(_){}
    }
    if(!rid) return;

    try{ localStorage.setItem("vsp_rid", rid); }catch(_){}

    try{
      const j = await fetchJSON(api("/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json"));
      const overall = j.overall || (j.data && j.data.overall) || "";
      const counts  = j.counts_total || (j.data && j.data.counts_total) || null;
      setOverallChip(overall);
      applyCounts(counts);
    }catch(_){
      // degrade silently: never crash page
    }
  }

  // run once + watch rid changes
  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", loadGateSummary);
  else loadGateSummary();

  let lastRid = getRid();
  setInterval(() => {
    const r = getRid();
    if(r && r !== lastRid){
      lastRid = r;
      loadGateSummary();
    }
  }, 1000);

  window.addEventListener("vsp:ridchange", loadGateSummary);
})();
 /* /''' + "$MARK" + r''' */
'''
    s = s.rstrip() + "\n\n" + inject + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", "$MARK")

PY

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] systemctl restart skipped/failed: $SVC"
fi

echo "[DONE] KPI+overall now read from run_gate_summary.json (commercial SOT)."
