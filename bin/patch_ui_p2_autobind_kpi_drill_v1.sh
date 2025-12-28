#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_autobind_drill_${TS}"
echo "[BACKUP] $F.bak_autobind_drill_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dashboard_enhance_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_AUTOBIND_KPI_DRILL_V1 ==="
if TAG in t:
    print("[OK] autobind already present, skip")
    raise SystemExit(0)

patch = r'''
// === VSP_P2_AUTOBIND_KPI_DRILL_V1 ===
// Auto bind drilldown for KPI cards (clickable commercial)
// - Uses dashboard_latest_v1.links if present
// - Fallback binds severity labels CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE
(function(){
  const SEVS = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function norm(s){ return String(s||"").trim().toUpperCase(); }

  function parseDrillToQuery(drill){
    // drill may be absolute/relative url to datasource, or a query-like string
    if (!drill) return "";
    let s = String(drill).trim();
    // if full URL, take hash or query
    try{
      if (s.startsWith("http")){
        const u = new URL(s);
        if (u.hash && u.hash.length > 1) return u.hash.replace(/^#\/?/,"");
        if (u.search && u.search.length > 1) return u.search.replace(/^\?/,"");
      }
    }catch(_){}
    // if starts with #...
    s = s.replace(/^#\/?/,"");
    // remove leading vsp4 path fragments
    s = s.replace(/^\/?vsp4\??/,"").replace(/^\?/,"");
    return s;
  }

  async function fetchDash(){
    const r = await fetch("/api/vsp/dashboard_latest_v1", {cache:"no-store"});
    return await r.json();
  }

  function bindEl(el, query){
    if (!el || !query) return;
    // do not double bind
    if (el.getAttribute("data-drill")) return;
    el.setAttribute("data-drill", query);
    el.style.cursor = "pointer";
    el.title = el.title || "Click to drilldown";
  }

  function findKpiCandidates(){
    // broad selectors; harmless if none
    const sels = [
      ".vsp-kpi-card", ".kpi-card", ".kpi", ".vsp-card",
      "[data-kpi]", "[data-kpi-card]", "[data-role='kpi']"
    ];
    const out = [];
    for (const s of sels){
      qsa(s).forEach(x=>out.push(x));
    }
    // fallback: any card-like divs in dashboard area
    const dash = qs("#vsp-dashboard-main") || qs("#tab-dashboard") || document.body;
    qsa("div", dash).forEach(d=>{
      const txt = norm(d.innerText||"");
      if (SEVS.some(s=>txt.includes(s)) && (d.offsetWidth>80 && d.offsetHeight>40)){
        out.push(d);
      }
    });
    // unique
    return Array.from(new Set(out));
  }

  function bestEffortBindFromLinks(links){
    // expected shapes:
    // links: { severity: {HIGH:"tab=datasource&sev=HIGH"...}, all:"...", suppressed:"..." }
    if (!links || typeof links !== "object") return false;
    const kpis = findKpiCandidates();
    let bound = 0;

    // bind severity-based
    for (const sev of SEVS){
      const drill = links?.severity?.[sev] || links?.["severity."+sev] || links?.[sev] || null;
      if (!drill) continue;
      const q = parseDrillToQuery(drill);
      if (!q) continue;
      for (const el of kpis){
        const txt = norm(el.innerText||"");
        if (txt.includes(sev)){
          bindEl(el, q);
          bound++;
        }
      }
    }

    // bind "all" if present
    if (links.all){
      const q = parseDrillToQuery(links.all);
      if (q){
        for (const el of kpis){
          const txt = norm(el.innerText||"");
          if (txt.includes("TOTAL") || txt.includes("ALL") || txt.includes("FINDINGS")){
            bindEl(el, q);
            bound++;
          }
        }
      }
    }
    return bound > 0;
  }

  function fallbackBindSev(){
    const kpis = findKpiCandidates();
    let bound = 0;
    for (const sev of SEVS){
      const q = "tab=datasource&sev=" + encodeURIComponent(sev) + "&limit=200";
      for (const el of kpis){
        const txt = norm(el.innerText||"");
        if (txt.includes(sev)){
          bindEl(el, q);
          bound++;
        }
      }
    }
    return bound>0;
  }

  async function init(){
    try{
      const j = await fetchDash();
      const links = j?.links || j?.drilldown || j?.drill || null;
      const ok = bestEffortBindFromLinks(links);
      if (!ok) fallbackBindSev();
    }catch(e){
      fallbackBindSev();
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
'''
p.write_text(t.rstrip() + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended KPI drill autobind")
PY

node --check static/js/vsp_dashboard_enhance_v1.js
echo "[OK] node --check OK"
echo "[DONE] Autobind KPI drill patch applied. Hard refresh Ctrl+Shift+R."
