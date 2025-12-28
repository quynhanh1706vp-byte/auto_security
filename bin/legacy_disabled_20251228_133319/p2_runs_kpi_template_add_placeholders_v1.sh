#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_kpi_placeholders_${TS}"
echo "[BACKUP] ${TPL}.bak_kpi_placeholders_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_RUNS_KPI_PLACEHOLDERS_V1"
if marker in s:
    print("[OK] KPI placeholders already present")
    raise SystemExit(0)

kpi_block = textwrap.dedent(r"""
<!-- ===================== VSP_P2_RUNS_KPI_PLACEHOLDERS_V1 ===================== -->
<div id="vsp_runs_kpi_compact_panel" style="margin:8px 0 10px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.12);border-radius:12px;background:rgba(2,6,23,.25)">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:center">
      <div style="min-width:140px">
        <div style="font-size:11px;color:#94a3b8">Runs (window)</div>
        <div id="vsp_runs_kpi_total_runs_window" style="font-size:18px;font-weight:700">—</div>
      </div>
      <div>
        <div style="font-size:11px;color:#94a3b8">GREEN</div>
        <div id="vsp_runs_kpi_GREEN" style="font-size:16px;font-weight:700">—</div>
      </div>
      <div>
        <div style="font-size:11px;color:#94a3b8">AMBER</div>
        <div id="vsp_runs_kpi_AMBER" style="font-size:16px;font-weight:700">—</div>
      </div>
      <div>
        <div style="font-size:11px;color:#94a3b8">RED</div>
        <div id="vsp_runs_kpi_RED" style="font-size:16px;font-weight:700">—</div>
      </div>
      <div>
        <div style="font-size:11px;color:#94a3b8">UNKNOWN</div>
        <div id="vsp_runs_kpi_UNKNOWN" style="font-size:16px;font-weight:700">—</div>
      </div>
      <div style="min-width:120px">
        <div style="font-size:11px;color:#94a3b8">Has findings</div>
        <div id="vsp_runs_kpi_findings" style="font-size:16px;font-weight:700">—</div>
      </div>
      <div style="min-width:120px">
        <div style="font-size:11px;color:#94a3b8">Latest RID</div>
        <div id="vsp_runs_kpi_latest" style="font-size:12px;color:#cbd5e1;max-width:320px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">—</div>
      </div>
    </div>

    <div style="display:flex;gap:8px;align-items:center">
      <span style="font-size:12px;color:#94a3b8">Window</span>
      <select id="vsp_runs_kpi_window_days" class="vsp_input" style="height:32px;padding:6px 10px;border-radius:10px">
        <option value="7">7 days</option>
        <option value="14">14 days</option>
        <option value="30" selected>30 days</option>
        <option value="90">90 days</option>
      </select>
      <button id="vsp_runs_kpi_reload_btn" class="vsp_btn" style="height:32px;border-radius:10px">Reload KPI</button>
    </div>
  </div>

  <div id="vsp_runs_kpi_meta" style="margin-top:6px;font-size:11px;color:#94a3b8"></div>
</div>
<!-- ===================== /VSP_P2_RUNS_KPI_PLACEHOLDERS_V1 ===================== -->
""").strip("\n")

# Insert right before the first compact trend container
pat = r'(<div\s+id="vsp_runs_kpi_trend_overall_compact"\s*>\s*</div>)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find vsp_runs_kpi_trend_overall_compact in template")

s2 = re.sub(pat, kpi_block + r"\n\1", s, count=1)
tpl.write_text(s2, encoding="utf-8")
print("[OK] inserted KPI placeholders above compact trends")
PY

echo "[DONE] p2_runs_kpi_template_add_placeholders_v1"
