#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_trend_runs_${TS}"
echo "[BACKUP] ${JS}.bak_trend_runs_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_TREND_FROM_RUNS_V1"
if marker in s:
    print("[OK] trend block already present")
    raise SystemExit(0)

append = r"""
/* ===================== VSP_P2_RUNS_KPI_TREND_FROM_RUNS_V1 ===================== */
async function fetchRunsForTrend(limit){
  const u = `/api/vsp/runs?limit=${encodeURIComponent(String(limit||400))}&offset=0`;
  const r = await fetch(u, {cache:"no-store"});
  const j = await r.json();
  // accept: array OR {runs:[...]} OR {items:[...]}
  if (Array.isArray(j)) return j;
  if (j && Array.isArray(j.runs)) return j.runs;
  if (j && Array.isArray(j.items)) return j.items;
  return [];
}

function dateKeyFromRun(x){
  const raw = String((x && (x.date||x.ts||x.time||x.created_at)) || "");
  // try YYYY-MM-DD
  const m = raw.match(/(\d{4}-\d{2}-\d{2})/);
  if (m) return m[1];
  return raw.slice(0,10);
}

function overallFromRun(x){
  const o = (x && (x.overall||x.status||x.result)) || "";
  const v = String(o).toUpperCase();
  if (v.includes("GREEN")) return "GREEN";
  if (v.includes("AMBER")) return "AMBER";
  if (v.includes("RED")) return "RED";
  if (v.includes("UNKNOWN")) return "UNKNOWN";
  return "UNKNOWN";
}

function renderOverallTrendText(rows){
  const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
  if (!root) return;

  if (!rows || !rows.length){
    root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
    return;
  }

  const head = `
    <div style="display:flex;gap:10px;align-items:center;margin-top:8px;margin-bottom:6px">
      <div style="font-weight:700">Overall trend (compact)</div>
      <div style="color:#94a3b8;font-size:12px">(last ${rows.length} days)</div>
    </div>
  `;
  const lines = rows.map(r=>{
    return `
      <div style="display:flex;gap:10px;align-items:center;padding:3px 0;border-top:1px solid rgba(148,163,184,.10)">
        <div style="width:92px;color:#cbd5e1;font-size:12px">${r.day}</div>
        <div style="display:flex;gap:10px;color:#94a3b8;font-size:12px;flex-wrap:wrap">
          <span>G:${r.GREEN}</span><span>A:${r.AMBER}</span><span>R:${r.RED}</span><span>U:${r.UNKNOWN}</span>
        </div>
      </div>
    `;
  }).join("");

  root.innerHTML = head + `<div style="border:1px solid rgba(148,163,184,.10);border-radius:10px;padding:6px 10px;background:rgba(2,6,23,.18)">${lines}</div>`;
}

async function fillOverallTrendFromRuns(days){
  try{
    const runs = await fetchRunsForTrend(500);
    const byDay = {};
    for (const x of runs){
      const d = dateKeyFromRun(x);
      if (!d || d.length < 8) continue;
      const o = overallFromRun(x);
      byDay.setdefault = byDay.setdefault || null; // harmless for old engines
      if (!byDay[d]) byDay[d] = {GREEN:0,AMBER:0,RED:0,UNKNOWN:0};
      byDay[d][o] = (byDay[d][o]||0) + 1;
    }
    const keys = Object.keys(byDay).sort(); // YYYY-MM-DD
    const last = keys.slice(-14).map(k=>({day:k, ...byDay[k]}));
    renderOverallTrendText(last);
  }catch(e){
    const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
    if (root) root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
  }
}

function fillSevTrendPlaceholder(){
  const root = document.getElementById("vsp_runs_kpi_trend_sev_compact");
  if (!root) return;
  root.innerHTML = '<div style="margin-top:10px;color:#94a3b8;font-size:12px">CRITICAL/HIGH trend: pending (will wire from run_gate_summary / unified findings)</div>';
}

/* hook into existing fillKpi() if present */
(function(){
  const _orig = (typeof window.fillKpi === "function") ? window.fillKpi : null;
  if (_orig){
    window.fillKpi = async function(days){
      const r = await _orig(days);
      // fire-and-forget lightweight trend
      fillOverallTrendFromRuns(days||30);
      fillSevTrendPlaceholder();
      return r;
    };
  }else{
    // if fillKpi not global, just run once on DOMReady
    document.addEventListener("DOMContentLoaded", ()=>{
      fillOverallTrendFromRuns(30);
      fillSevTrendPlaceholder();
    });
  }
})();
"""
p.write_text(s + "\n" + append + "\n", encoding="utf-8")
print("[OK] appended overall trend-from-runs block")
PY

node --check "$JS"
echo "[OK] node --check OK"
echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
