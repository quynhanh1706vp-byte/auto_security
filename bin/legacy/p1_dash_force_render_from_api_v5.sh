#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# Candidates that likely run on /vsp5
FILES=(
  "static/js/vsp_dashboard_live_v2.V1_baseline.js"
  "static/js/vsp_charts_live_v2.js"
  "static/js/vsp_ui_main.js"
  "static/js/vsp_vertical.js"
)

python3 - <<'PY'
from pathlib import Path

MARK="VSP_P1_DASH_FORCE_RENDER_FROM_API_V5"
js_block = r"""
// VSP_P1_DASH_FORCE_RENDER_FROM_API_V5
(function(){
  if (window.__VSP_DASH_RENDER_V5) return;
  window.__VSP_DASH_RENDER_V5 = true;

  function pickCanvas(ids){
    for (const id of ids){
      const el = document.getElementById(id);
      if (el && typeof el.getContext === "function") return el;
    }
    return null;
  }

  async function getLatestRid(){
    try{
      const r = await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
      const j = await r.json();
      return (j && j.items && j.items[0] && j.items[0].run_id) ? j.items[0].run_id : "";
    }catch(e){ return ""; }
  }

  function getRidFromUrl(){
    try{
      const u = new URL(window.location.href);
      return u.searchParams.get("rid") || "";
    }catch(e){ return ""; }
  }

  function parseDonut(j){
    if (j && j.charts && j.charts.severity && j.charts.severity.donut) return j.charts.severity.donut;
    if (j && j.donut && j.donut.labels && j.donut.values) return j.donut;
    if (j && Array.isArray(j.severity_distribution)){
      return { labels: j.severity_distribution.map(x=>x.sev), values: j.severity_distribution.map(x=>x.count) };
    }
    if (j && Array.isArray(j.sev_dist)){
      return { labels: j.sev_dist.map(x=>x.sev), values: j.sev_dist.map(x=>x.count) };
    }
    return null;
  }

  function parseTrend(j){
    if (j && j.charts && j.charts.trend && j.charts.trend.series) return j.charts.trend.series;
    if (j && j.trend && j.trend.labels && j.trend.values) return j.trend;
    if (j && Array.isArray(j.findings_trend)){
      return { labels: j.findings_trend.map(x=>x.rid), values: j.findings_trend.map(x=>x.total) };
    }
    return null;
  }

  function parseBarCritHigh(j){
    if (j && j.charts && j.charts.crit_high_by_tool && j.charts.crit_high_by_tool.bar) return j.charts.crit_high_by_tool.bar;
    if (j && j.bar_crit_high && j.bar_crit_high.labels) return j.bar_crit_high;
    if (j && Array.isArray(j.critical_high_by_tool)){
      const labels = j.critical_high_by_tool.map(x=>x.tool);
      const crit = j.critical_high_by_tool.map(x=>x.critical||0);
      const high = j.critical_high_by_tool.map(x=>x.high||0);
      return { labels, series: [{name:"CRITICAL",data:crit},{name:"HIGH",data:high}] };
    }
    return null;
  }

  function renderDonut(donut){
    if (!window.Chart || !donut) return;
    const canvas = pickCanvas([
      "severity_donut_chart","chart-severity-donut","severity_donut",
      "vsp_chart_ds_severity","vsp-ds-severity-donut","chart_severity_donut"
    ]);
    if (!canvas) return;
    try{ window.__VSP_DONUT_CHART_V5 && window.__VSP_DONUT_CHART_V5.destroy(); }catch(e){}
    window.__VSP_DONUT_CHART_V5 = new Chart(canvas, {
      type: "doughnut",
      data: { labels: donut.labels, datasets: [{ data: donut.values }] },
      options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } } }
    });
  }

  function renderTrend(tr){
    if (!window.Chart || !tr) return;
    const canvas = pickCanvas([
      "findings_trend_chart","chart-findings-trend","findings_trend",
      "vsp_chart_trend","chart_findings_trend"
    ]);
    if (!canvas) return;
    try{ window.__VSP_TREND_CHART_V5 && window.__VSP_TREND_CHART_V5.destroy(); }catch(e){}
    window.__VSP_TREND_CHART_V5 = new Chart(canvas, {
      type: "line",
      data: { labels: tr.labels, datasets: [{ data: tr.values }] },
      options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } } }
    });
  }

  function renderBar(bar){
    if (!window.Chart || !bar) return;
    const canvas = pickCanvas([
      "critical_high_by_tool_chart","chart-critical-high-by-tool","crit_high_by_tool",
      "vsp_chart_crit_high","chart_crit_high"
    ]);
    if (!canvas) return;
    const s0 = (bar.series && bar.series[0]) ? bar.series[0].data : [];
    const s1 = (bar.series && bar.series[1]) ? bar.series[1].data : [];
    try{ window.__VSP_BAR_CHART_V5 && window.__VSP_BAR_CHART_V5.destroy(); }catch(e){}
    window.__VSP_BAR_CHART_V5 = new Chart(canvas, {
      type: "bar",
      data: {
        labels: bar.labels,
        datasets: [
          { label: "CRITICAL", data: s0 },
          { label: "HIGH", data: s1 }
        ]
      },
      options: { responsive:true, maintainAspectRatio:false }
    });
  }

  async function main(){
    try{
      let rid = getRidFromUrl();
      if (!rid) rid = await getLatestRid();
      if (!rid) return;

      const r = await fetch("/api/vsp/dash_charts?rid=" + encodeURIComponent(rid), {cache:"no-store"});
      const j = await r.json();

      renderDonut(parseDonut(j));
      renderTrend(parseTrend(j));
      renderBar(parseBarCritHigh(j));
    }catch(e){
      console.warn("[VSP][DASH][V5] render failed:", e);
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
"""

def patch_file(fp: Path):
    if not fp.exists(): return False, "missing"
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s: return False, "already"
    fp.write_text(s + "\n\n" + js_block + "\n", encoding="utf-8")
    return True, "patched"

targets = [
    Path("static/js/vsp_dashboard_live_v2.V1_baseline.js"),
    Path("static/js/vsp_charts_live_v2.js"),
    Path("static/js/vsp_ui_main.js"),
    Path("static/js/vsp_vertical.js"),
]

done = []
for t in targets:
    ok, why = patch_file(t)
    if ok:
        done.append(str(t))

print("[OK] patched_files:", done)
PY

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p'
