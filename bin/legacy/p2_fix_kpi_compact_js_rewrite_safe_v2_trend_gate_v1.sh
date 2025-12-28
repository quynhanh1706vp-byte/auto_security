#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_runs_kpi_compact_v3.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [1] backup =="
cp -f "$JS" "${JS}.bak_safe2_trend_gate_${TS}"
echo "[BACKUP] ${JS}.bak_safe2_trend_gate_${TS}"

echo "== [2] rewrite JS (safe2 + trend from gate summaries) =="
python3 - <<'PY'
from pathlib import Path
import textwrap

Path("static/js/vsp_runs_kpi_compact_v3.js").write_text(textwrap.dedent(r"""
/* VSP_P2_RUNS_KPI_COMPACT_V3_SAFE2 (KPI v2 + Overall trend from gate_summary; NO canvas; DOMReady; single-flight) */
(()=> {
  if (window.__vsp_runs_kpi_compact_v3_safe2) return;
  window.__vsp_runs_kpi_compact_v3_safe2 = true;

  const $ = (q)=> document.querySelector(q);

  // single-flight + throttle
  let __kpi_inflight = false;
  let __kpi_last_ts = 0;
  let __kpi_last_days = null;

  let __trend_inflight = false;
  let __trend_last_ts = 0;

  function setText(id, v){
    const el = document.getElementById(id);
    if (!el) return false;
    el.textContent = (v===null || v===undefined || v==="") ? "—" : String(v);
    return true;
  }

  function hideHeavyCanvases(){
    const c1 = document.getElementById("vsp_runs_kpi_canvas_overall");
    const c2 = document.getElementById("vsp_runs_kpi_canvas_sev");
    const w1 = document.getElementById("vsp_runs_kpi_canvas_wrap_overall") || (c1? c1.parentElement : null);
    const w2 = document.getElementById("vsp_runs_kpi_canvas_wrap_sev") || (c2? c2.parentElement : null);
    if (w1) w1.style.display = "none";
    if (w2) w2.style.display = "none";
  }

  async function fetchKpi(days){
    const now = Date.now();
    const d = String(days || 30);

    if (__kpi_inflight) return null;
    if (__kpi_last_days === d && (now - __kpi_last_ts) < 2500) return null;

    __kpi_inflight = true;
    __kpi_last_days = d;
    __kpi_last_ts = now;

    const q = encodeURIComponent(d);
    const urls = [`/api/ui/runs_kpi_v2?days=${q}`, `/api/ui/runs_kpi_v1?days=${q}`];

    let lastErr = null;
    try{
      for (const u of urls){
        try{
          const r = await fetch(u, {cache:"no-store"});
          const j = await r.json();
          if (j && j.ok) return j;
          lastErr = new Error(j?.err || j?.error || "not ok");
        }catch(e){ lastErr = e; }
      }
      throw lastErr || new Error("kpi fetch failed");
    }finally{
      __kpi_inflight = false;
    }
  }

  function renderNoTrend(rootId){
    const root = document.getElementById(rootId);
    if (!root) return;
    root.innerHTML = '<div style="color:#94a3b8;font-size:12px">No trend data</div>';
  }

  function renderOverallTrendCompact(rows){
    const root = document.getElementById("vsp_runs_kpi_trend_overall_compact");
    if (!root) return;

    if (!rows || !rows.length){
      renderNoTrend("vsp_runs_kpi_trend_overall_compact");
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

  function normOverall(v){
    const s = String(v||"").toUpperCase();
    if (s.includes("GREEN") || s==="PASS" || s==="OK") return "GREEN";
    if (s.includes("AMBER") || s==="WARN") return "AMBER";
    if (s.includes("RED") || s==="FAIL" || s==="ERROR") return "RED";
    return "UNKNOWN";
  }

  function dateKeyFromRunId(rid){
    const s = String(rid||"");
    // RUN_YYYYmmdd_HHMMSS
    let m = s.match(/RUN_(\d{4})(\d{2})(\d{2})_\d{6}/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    // VSP_CI_RUN_YYYYmmdd_HHMMSS
    m = s.match(/VSP_CI_RUN_(\d{4})(\d{2})(\d{2})_\d{6}/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    // RUN_anything_YYYYmmdd_HHMMSS  (e.g., RUN_khach6_FULL_20251129_133030)
    m = s.match(/_(\d{4})(\d{2})(\d{2})_\d{6}/);
    if (m) return `${m[1]}-${m[2]}-${m[3]}`;
    return "";
  }

  async function fetchRunsList(limit){
    const u = `/api/vsp/runs?limit=${encodeURIComponent(String(limit||500))}&offset=0`;
    const r = await fetch(u, {cache:"no-store"});
    const j = await r.json();
    if (j && Array.isArray(j.items)) return j.items;
    if (j && Array.isArray(j.runs)) return j.runs;
    if (Array.isArray(j)) return j;
    return [];
  }

  async function fetchGateSummary(rid, gateSource){
    const path = gateSource || "run_gate_summary.json";
    const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(String(rid))}&path=${encodeURIComponent(String(path))}`;
    const r = await fetch(u, {cache:"no-store"});
    const j = await r.json().catch(()=>null);
    // some gateways may return {"ok":false,...}
    if (j && j.ok === false) return null;
    return j;
  }

  async function runPool(tasks, concurrency){
    const out = [];
    let i = 0;
    const n = tasks.length;
    const workers = Array.from({length: Math.max(1, concurrency||4)}, async ()=>{
      while (i < n){
        const idx = i++;
        try{ out[idx] = await tasks[idx](); }
        catch(e){ out[idx] = null; }
      }
    });
    await Promise.all(workers);
    return out;
  }

  async function fillOverallTrendFromGateSummaries(){
    const now = Date.now();
    if (__trend_inflight) return;
    if ((now - __trend_last_ts) < 8000) return; // hard throttle
    __trend_inflight = true;
    __trend_last_ts = now;

    try{
      const items = await fetchRunsList(500);
      if (!items || !items.length){
        renderNoTrend("vsp_runs_kpi_trend_overall_compact");
        return;
      }

      // collect newest -> last 14 distinct days
      const byDay = {};
      const dayOrder = [];
      for (const it of items){
        const rid = it.run_id || it.rid || it.id || it.runId;
        const d = dateKeyFromRunId(rid);
        if (!d) continue;
        if (!byDay[d]){
          byDay[d] = [];
          dayOrder.push(d);
          if (dayOrder.length >= 14) break;
        }
        byDay[d].push({
          rid,
          gate_source: (it.gate_source) || (it.has && it.has.gate_source) || (it.has && it.has.gateSource) || null
        });
      }

      const days = dayOrder.slice().sort(); // chronological
      const rows = [];
      // Build tasks only for runs we care about (<= 14 days)
      const tasks = [];
      const meta = [];
      for (const d of days){
        for (const r of (byDay[d]||[])){
          meta.push({day:d, rid:r.rid, gate_source:r.gate_source});
          tasks.push(()=> fetchGateSummary(r.rid, r.gate_source));
        }
      }

      const res = await runPool(tasks, 4);

      // aggregate
      const agg = {};
      for (let k=0;k<meta.length;k++){
        const m = meta[k];
        const j = res[k];
        const overall = normOverall(j?.overall_status || j?.overall || j?.status || j?.result);
        if (!agg[m.day]) agg[m.day] = {GREEN:0,AMBER:0,RED:0,UNKNOWN:0};
        agg[m.day][overall] = (agg[m.day][overall]||0) + 1;
      }

      for (const d of days){
        const x = agg[d] || {GREEN:0,AMBER:0,RED:0,UNKNOWN:0};
        rows.push({day:d, ...x});
      }

      renderOverallTrendCompact(rows);
    }catch(e){
      renderNoTrend("vsp_runs_kpi_trend_overall_compact");
    }finally{
      __trend_inflight = false;
    }
  }

  async function fillKpi(days){
    hideHeavyCanvases();

    const j = await fetchKpi(days);
    if (!j) return;

    setText("vsp_runs_kpi_total_runs_window", j.total_runs ?? j.total ?? "—");
    setText("vsp_runs_kpi_GREEN",   j.by_overall?.GREEN   ?? "—");
    setText("vsp_runs_kpi_AMBER",   j.by_overall?.AMBER   ?? "—");
    setText("vsp_runs_kpi_RED",     j.by_overall?.RED     ?? "—");
    setText("vsp_runs_kpi_UNKNOWN", j.by_overall?.UNKNOWN ?? "—");
    setText("vsp_runs_kpi_findings", j.has_findings ?? "—");
    setText("vsp_runs_kpi_latest", j.latest_rid ?? "—");

    const meta = document.getElementById("vsp_runs_kpi_meta");
    if (meta){
      const ts = j.ts ? new Date((Number(j.ts)||0)*1000).toLocaleString() : "";
      meta.textContent = `window=${days||30}d • has_gate=${j.has_gate ?? "—"} • ts=${ts}`;
    }

    // after KPI, fill trend (light + throttled)
    fillOverallTrendFromGateSummaries();
  }

  function boot(){
    hideHeavyCanvases();

    const sel = document.getElementById("vsp_runs_kpi_window_days");
    const btn = document.getElementById("vsp_runs_kpi_reload_btn");

    const getDays = ()=>{
      const v = sel ? String(sel.value||"30") : "30";
      const n = parseInt(v,10);
      return Number.isFinite(n) ? n : 30;
    };

    if (btn){
      btn.addEventListener("click", ()=> fillKpi(getDays()));
    }
    if (sel){
      sel.addEventListener("change", ()=> fillKpi(getDays()));
    }

    // initial
    fillKpi(getDays());
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", boot);
  }else{
    boot();
  }
})();
""").strip()+"\n", encoding="utf-8")
print("[OK] wrote safe2 KPI JS with overall trend from gate summaries")
PY

echo "== [3] syntax check =="
node --check "$JS"
echo "[OK] node --check OK"

echo "== [4] sanity endpoints =="
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo

echo
echo "[DONE] Hard reload /runs (Ctrl+Shift+R). Trend should appear within a few seconds."
