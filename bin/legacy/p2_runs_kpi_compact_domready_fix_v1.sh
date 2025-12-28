#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_domready_${TS}"
echo "[BACKUP] ${JS}.bak_domready_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_COMPACT_DOMREADY_V1"
if marker in s:
    print("[OK] domready patch already present")
    raise SystemExit(0)

# 1) disable any immediate auto-run if exists (best-effort)
# (some earlier versions may have loadRunsKpi() called directly)
s = re.sub(r'\n\s*(loadRunsKpi|loadKpi|boot)\s*\(\s*\)\s*;\s*\n', '\n', s)

append = textwrap.dedent(r"""
  // ===================== VSP_P2_RUNS_KPI_COMPACT_DOMREADY_V1 =====================
  function getDays(){
    // prefer any existing window select, otherwise default 30
    const sel = document.getElementById("vsp_runs_kpi_window") ||
                document.getElementById("vsp_runs_kpi_window_days") ||
                document.querySelector('select[data-kpi-window]') ||
                null;
    let v = 30;
    try{
      if (sel && sel.value) v = parseInt(String(sel.value), 10);
    }catch(_){}
    if (!v || isNaN(v)) v = 30;
    v = Math.max(1, Math.min(v, 3650));
    return v;
  }

  function setAny(ids, v){
    let ok = false;
    for (const id of ids){
      if (setText(id, v)) ok = true;
    }
    return ok;
  }

  function fillKpi(j, days){
    // Support multiple possible id names (keeps layout stable even if template changed)
    setAny(["vsp_runs_kpi_total","vsp_runs_kpi_total_runs","vsp_runs_kpi_total_runs_window"], j.total_runs);
    setAny(["vsp_runs_kpi_green","vsp_runs_kpi_GREEN"], j.by_overall?.GREEN ?? 0);
    setAny(["vsp_runs_kpi_amber","vsp_runs_kpi_AMBER"], j.by_overall?.AMBER ?? 0);
    setAny(["vsp_runs_kpi_red","vsp_runs_kpi_RED"], j.by_overall?.RED ?? 0);
    setAny(["vsp_runs_kpi_unknown","vsp_runs_kpi_UNKNOWN"], j.by_overall?.UNKNOWN ?? 0);
    setAny(["vsp_runs_kpi_has_findings","vsp_runs_kpi_findings"], j.has_findings ?? "—");
    setAny(["vsp_runs_kpi_has_gate","vsp_runs_kpi_gate"], j.has_gate ?? "—");
    setAny(["vsp_runs_kpi_latest_rid","vsp_runs_kpi_latest"], j.latest_rid ?? "—");

    // optional meta line
    const meta = document.getElementById("vsp_runs_kpi_meta");
    if (meta){
      meta.textContent = `window=${days}d • total=${j.total_runs ?? "—"} • has_gate=${j.has_gate ?? "—"} • ts=${j.ts ?? ""}`;
    }
  }

  async function runOnce(){
    try{
      hideIfBlankCanvas(); // keep layout safe (no giant white blocks)
      const days = getDays();
      const j = await fetchKpi(days);
      fillKpi(j, days);
    }catch(e){
      console.warn("[RUNS_KPI] failed:", e && (e.message || e));
      const meta = document.getElementById("vsp_runs_kpi_meta");
      if (meta) meta.textContent = "KPI load failed. Check API v2/v1 + console.";
    }
  }

  function bootDomReady(){
    // delay a bit to avoid blocking render
    setTimeout(runOnce, 60);

    // wire reload button if exists
    const btn = document.getElementById("vsp_runs_kpi_reload") ||
                document.getElementById("vsp_runs_kpi_reload_btn") ||
                document.querySelector('[data-kpi-reload]') ||
                null;
    if (btn){
      btn.addEventListener("click", (ev)=>{ ev.preventDefault(); runOnce(); });
    }

    // wire window select if exists
    const sel = document.getElementById("vsp_runs_kpi_window") ||
                document.getElementById("vsp_runs_kpi_window_days") ||
                document.querySelector('select[data-kpi-window]') ||
                null;
    if (sel){
      sel.addEventListener("change", ()=> runOnce());
    }
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", bootDomReady, {once:true});
  }else{
    bootDomReady();
  }
  // ===================== /VSP_P2_RUNS_KPI_COMPACT_DOMREADY_V1 =====================
""").strip("\n") + "\n"

# 2) insert right before the final "})();" (IIFE end)
idx = s.rfind("})();")
if idx == -1:
    # fallback: append at end
    s2 = s + "\n" + append
else:
    s2 = s[:idx] + "\n" + append + "\n" + s[idx:]

p.write_text(s2, encoding="utf-8")
print("[OK] appended domready boot + fillKpi")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_compact_domready_fix_v1"
