#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_kpi_compact_v3.js"
cp -f "$JS" "${JS}.bak_hardfill_${TS}"
echo "[BACKUP] ${JS}.bak_hardfill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap
p = Path("static/js/vsp_runs_kpi_compact_v3.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_KPI_HARDFILL_IDS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

blk = textwrap.dedent(r"""
/* ===================== VSP_P2_KPI_HARDFILL_IDS_V1 ===================== */
(()=> {
  function $id(x){ return document.getElementById(x); }
  function set(id, v){ const el=$id(id); if(!el) return; el.textContent = (v===null||v===undefined)?"—":String(v); }

  async function go(){
    try{
      const sel = $id("vsp_runs_kpi_window_days");
      const days = sel ? (sel.value||"30") : "30";
      const r = await fetch(`/api/ui/runs_kpi_v2?days=${encodeURIComponent(days)}`, {cache:"no-store"});
      const j = await r.json();
      if(!j || !j.ok) return;

      set("vsp_runs_kpi_total_runs_window", j.total_runs);
      set("vsp_runs_kpi_GREEN",   j.by_overall?.GREEN ?? 0);
      set("vsp_runs_kpi_AMBER",   j.by_overall?.AMBER ?? 0);
      set("vsp_runs_kpi_RED",     j.by_overall?.RED ?? 0);
      set("vsp_runs_kpi_UNKNOWN", j.by_overall?.UNKNOWN ?? 0);
      set("vsp_runs_kpi_findings", j.has_findings ?? "—");
      set("vsp_runs_kpi_latest", j.latest_rid ?? "—");
      const meta = $id("vsp_runs_kpi_meta");
      if(meta) meta.textContent = `window=${days}d • total=${j.total_runs} • ts=${j.ts}`;
    }catch(_){}
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(go, 30), {once:true});
  }else{
    setTimeout(go, 30);
  }
  const btn = $id("vsp_runs_kpi_reload_btn");
  if(btn) btn.addEventListener("click", (e)=>{ e.preventDefault(); go(); });
  const sel = $id("vsp_runs_kpi_window_days");
  if(sel) sel.addEventListener("change", ()=> go());
})();
 /* ===================== /VSP_P2_KPI_HARDFILL_IDS_V1 ===================== */
""").strip()+"\n"

# append before final IIFE close if exists
idx = s.rfind("})();")
if idx != -1:
    s2 = s[:idx] + "\n" + blk + "\n" + s[idx:]
else:
    s2 = s + "\n" + blk
p.write_text(s2, encoding="utf-8")
print("[OK] appended hardfill block")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_compact_hardfill_ids_v1"
