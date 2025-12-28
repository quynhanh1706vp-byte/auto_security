#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TPL="templates/vsp_runs_reports_v1.html"
JS="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_kpi_bindv2_${TS}"
cp -f "$JS"  "${JS}.bak_kpi_bindv2_${TS}"
echo "[BACKUP] ${TPL}.bak_kpi_bindv2_${TS}"
echo "[BACKUP] ${JS}.bak_kpi_bindv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

panel = textwrap.dedent(r"""
<!-- ===================== VSP_P2_RUNS_KPI_PANEL_V2 ===================== -->
<section class="vsp-card" id="vsp_runs_kpi_panel_v2" style="margin:14px 0 10px 0;">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
    <div style="display:flex;flex-direction:column;gap:2px;">
      <div style="font-weight:700;font-size:16px;letter-spacing:.2px;">Runs — Operational KPI</div>
      <div style="opacity:.75;font-size:12px;" id="vsp_runs_kpi_status_v2">Loading…</div>
    </div>
    <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
      <label style="font-size:12px;opacity:.8;">Window</label>
      <select id="vsp_runs_kpi_days_v2" class="vsp-input" style="min-width:110px;">
        <option value="7">7 days</option>
        <option value="14">14 days</option>
        <option value="30" selected>30 days</option>
        <option value="90">90 days</option>
        <option value="365">365 days</option>
      </select>
      <button id="vsp_runs_kpi_reload_v2" class="vsp-btn" type="button">Reload KPI</button>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:repeat(6,minmax(140px,1fr));gap:10px;margin-top:10px;">
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">Runs (window)</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_total_v2">—</div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">GREEN</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_green_v2">—</div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">AMBER</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_amber_v2">—</div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">RED</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_red_v2">—</div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">UNKNOWN</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_unknown_v2">—</div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="opacity:.75;font-size:12px;">Has findings</div>
      <div style="font-size:22px;font-weight:800;" id="vsp_kpi_has_findings_v2">—</div>
    </div>
  </div>

  <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:8px;opacity:.85;font-size:12px;">
    <div>Latest RID: <span id="vsp_kpi_latest_rid_v2">—</span></div>
  </div>

  <div style="opacity:.65;font-size:12px;margin-top:8px;">
    Trend charts need API fields (labels/series). If absent, UI shows “No trend data” but KPIs still update.
  </div>
</section>
<!-- ===================== /VSP_P2_RUNS_KPI_PANEL_V2 ===================== -->
""").strip()

# Replace old KPI panel if present, else insert after first H1 or after <main>
if "VSP_P2_RUNS_KPI_PANEL_V2" not in s:
    # remove old v1 panel if exists
    s = re.sub(r"(?s)<!--\s*====================\s*VSP_P2_RUNS_KPI_PANEL_V1.*?/VSP_P2_RUNS_KPI_PANEL_V1\s*====================\s*-->",
               "", s, count=1)
    if re.search(r"(?is)</h1>", s):
        s = re.sub(r"(?is)</h1>", lambda m: m.group(0) + "\n" + panel + "\n", s, count=1)
    elif re.search(r"(?is)<main[^>]*>", s):
        s = re.sub(r"(?is)(<main[^>]*>)", r"\1\n"+panel+"\n", s, count=1)
    else:
        s = panel + "\n" + s

tpl.write_text(s, encoding="utf-8")
print("[OK] patched KPI panel v2 into template")
PY

python3 - <<'PY'
from pathlib import Path
import time

js = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_BIND_V2"
if marker in s:
    print("[OK] KPI bind v2 already present")
else:
    block = r"""
/* VSP_P2_RUNS_KPI_BIND_V2 (schema adapter for /api/ui/runs_kpi_v1; sets KPI numbers even when trend absent) */
(()=> {
  if (window.__vsp_runs_kpi_bind_v2) return;
  window.__vsp_runs_kpi_bind_v2 = true;

  const $id = (id)=> document.getElementById(id);

  function set(id, v){
    const el = $id(id);
    if(el) el.textContent = (v===undefined || v===null) ? "—" : String(v);
  }

  async function fetchKpi(days){
    const url = `/api/ui/runs_kpi_v1?days=${encodeURIComponent(days||30)}`;
    const r = await fetch(url, {cache:"no-store"});
    const j = await r.json();
    if(!j || j.ok !== true) throw new Error(j?.err || "kpi api failed");
    return j;
  }

  async function reload(){
    const sel = $id("vsp_runs_kpi_days_v2");
    const days = sel ? (sel.value||"30") : "30";
    const st = $id("vsp_runs_kpi_status_v2");
    if(st) st.textContent = "Loading…";

    try{
      const j = await fetchKpi(days);
      const bo = j.by_overall || {};
      set("vsp_kpi_total_v2", j.total_runs ?? 0);
      set("vsp_kpi_green_v2", bo.GREEN ?? 0);
      set("vsp_kpi_amber_v2", bo.AMBER ?? 0);
      set("vsp_kpi_red_v2", bo.RED ?? 0);
      set("vsp_kpi_unknown_v2", bo.UNKNOWN ?? 0);
      set("vsp_kpi_has_findings_v2", j.has_findings ?? 0);
      set("vsp_kpi_latest_rid_v2", j.latest_rid ?? "—");

      if(st){
        st.textContent = `Window=${days}d • total=${j.total_runs ?? 0} • has_gate=${j.has_gate ?? "?"} • ts=${j.ts ?? ""}`.trim();
      }
    }catch(e){
      console.warn("[RUNS_KPI_BIND_V2] failed:", e);
      if(st) st.textContent = "KPI load failed (check /api/ui/runs_kpi_v1)";
    }
  }

  function hook(){
    const btn = $id("vsp_runs_kpi_reload_v2");
    if(btn && !btn.__hooked){
      btn.__hooked = true;
      btn.addEventListener("click", reload);
    }
    const sel = $id("vsp_runs_kpi_days_v2");
    if(sel && !sel.__hooked){
      sel.__hooked = true;
      sel.addEventListener("change", reload);
    }
    setTimeout(reload, 150);
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", hook);
  else hook();
})();
"""
    js.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended KPI bind v2 block")

PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_bind_v2_hotfix_v1"
