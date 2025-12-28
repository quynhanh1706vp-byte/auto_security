#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_trend_runs_${TS}"
echo "[BACKUP] ${JS}.bak_trend_runs_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_OVERALL_TREND_FROM_RUNS_V2"
if marker in s:
    print("[OK] trend block already present")
    raise SystemExit(0)

block = r"""
/* ===================== VSP_P2_RUNS_KPI_OVERALL_TREND_FROM_RUNS_V2 ===================== */
async function __vspFetchRunsForTrend(limit){
  const u = `/api/vsp/runs?limit=${encodeURIComponent(String(limit||500))}&offset=0`;
  const r = await fetch(u, {cache:"no-store"});
  const j = await r.json();
  if (Array.isArray(j)) return j;
  if (j && Array.isArray(j.runs)) return j.runs;
  if (j && Array.isArray(j.items)) return j.items;
  return [];
}

function __vspDateKeyFromAny(x){
  // Prefer explicit date fields
  const raw = String((x && (x.date || x.created_at || x.ts || x.time)) || "");
  const m = raw.match(/(\d{4}-\d{2}-\d{2})/);
  if (m) return m[1];

  // Fallback: parse RID like RUN_YYYYmmdd_HHMMSS
  const rid = String((x && (x.rid || x.run_id || x.id)) || "");
  const m2 = rid.match(/RUN_(\d{4})(\d{2})(\d{2})_/);
  if (m2) return `${m2[1]}-${m2[2]}-${m2[3]}`;

  // Last resort: empty => ignored
  return "";
}

function __vspOverallFromAny(x){
  const v = String((x && (x.overall || x.status || x.result)) || "").toUpperCase();
  if (v.includes("GREEN")) return "GREEN";
  if (v.includes("AMBER")) return "AMBER";
  if (v.includes("RED")) return "RED";
  return "UNKNOWN";
}

function __vspRenderOverallTrendCompact(rows){
  const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
  if (!root) return;

  if (!rows || !rows.length){
    root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
    return;
  }

  const head = `
    <div style="display:flex;gap:10px;align-items:center;margin-top:10px;margin-bottom:6px">
      <div style="font-weight:700">Overall trend (compact)</div>
      <div style="color:#94a3b8;font-size:12px">(last ${rows.length} days)</div>
    </div>
  `;

  const lines = rows.map(r=>{
    return `
      <div style="display:flex;gap:10px;align-items:center;padding:4px 0;border-top:1px solid rgba(148,163,184,.10)">
        <div style="width:92px;color:#cbd5e1;font-size:12px">${r.day}</div>
        <div style="display:flex;gap:12px;color:#94a3b8;font-size:12px;flex-wrap:wrap">
          <span>G:${r.GREEN}</span><span>A:${r.AMBER}</span><span>R:${r.RED}</span><span>U:${r.UNKNOWN}</span>
        </div>
      </div>
    `;
  }).join("");

  root.innerHTML = head + `<div style="border:1px solid rgba(148,163,184,.10);border-radius:10px;padding:6px 10px;background:rgba(2,6,23,.18)">${lines}</div>`;
}

async function __vspFillOverallTrendFromRuns(){
  try{
    const runs = await __vspFetchRunsForTrend(600);
    const byDay = {};
    for (const x of runs){
      const d = __vspDateKeyFromAny(x);
      if (!d) continue;
      const o = __vspOverallFromAny(x);
      if (!byDay[d]) byDay[d] = {GREEN:0,AMBER:0,RED:0,UNKNOWN:0};
      byDay[d][o] = (byDay[d][o]||0) + 1;
    }
    const days = Object.keys(byDay).sort();
    const last = days.slice(-14).map(d=>({day:d, ...byDay[d]}));
    __vspRenderOverallTrendCompact(last);
  }catch(e){
    const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
    if (root) root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
  }
}

// hook: after KPI fills, render trend (super light)
(function(){
  const _orig = (typeof window.fillKpi === "function") ? window.fillKpi : null;
  if (_orig){
    window.fillKpi = async function(days){
      const r = await _orig(days);
      // fire-and-forget
      __vspFillOverallTrendFromRuns();
      return r;
    };
  }else{
    document.addEventListener("DOMContentLoaded", ()=> __vspFillOverallTrendFromRuns());
  }
})();
"""

p.write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] appended overall trend-from-runs v2 block")
PY

node --check "$JS"
echo "[OK] node --check OK"

echo "== [SANITY] /api/vsp/runs reachable =="
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo
echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
