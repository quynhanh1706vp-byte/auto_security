#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

JS="static/js/vsp_charts_live_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_render_v6_${TS}"
echo "[BACKUP] ${JS}.bak_dash_render_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_charts_live_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_RENDER_V6_VSPCHART_IDS"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

blk = r"""
// VSP_P1_DASH_RENDER_V6_VSPCHART_IDS
(function(){
  if (window.__VSP_DASH_RENDER_V6) return;
  window.__VSP_DASH_RENDER_V6 = true;

  function ensureCanvas(holderId){
    const el = document.getElementById(holderId);
    if (!el) return null;
    if (el.tagName && el.tagName.toLowerCase() === "canvas") return el;

    // if holder is a div/card, create canvas inside
    let c = el.querySelector("canvas");
    if (!c) {
      c = document.createElement("canvas");
      c.width = 800; c.height = 260;
      c.style.width = "100%";
      c.style.height = "260px";
      el.innerHTML = "";
      el.appendChild(c);
    }
    return c;
  }

  async function getRid(){
    try{
      const u = new URL(window.location.href);
      const rid = u.searchParams.get("rid");
      if (rid) return rid;
    }catch(e){}
    try{
      const r = await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
      const j = await r.json();
      return (j && j.items && j.items[0] && j.items[0].run_id) ? j.items[0].run_id : "";
    }catch(e){ return ""; }
  }

  function parseDonut(j){
    if (j?.charts?.severity?.donut) return j.charts.severity.donut;
    if (j?.donut?.labels && j?.donut?.values) return j.donut;
    if (Array.isArray(j?.severity_distribution))
      return { labels: j.severity_distribution.map(x=>x.sev), values: j.severity_distribution.map(x=>x.count) };
    return null;
  }

  function parseTrend(j){
    if (j?.charts?.trend?.series) return j.charts.trend.series;
    if (j?.trend?.labels && j?.trend?.values) return j.trend;
    if (Array.isArray(j?.findings_trend))
      return { labels: j.findings_trend.map(x=>x.rid), values: j.findings_trend.map(x=>x.total) };
    return null;
  }

  function parseBarCritHigh(j){
    if (j?.charts?.crit_high_by_tool?.bar) return j.charts.crit_high_by_tool.bar;
    if (j?.bar_crit_high?.labels) return j.bar_crit_high;
    if (Array.isArray(j?.critical_high_by_tool)){
      const labels = j.critical_high_by_tool.map(x=>x.tool);
      const crit = j.critical_high_by_tool.map(x=>x.critical||0);
      const high = j.critical_high_by_tool.map(x=>x.high||0);
      return { labels, series: [{name:"CRITICAL",data:crit},{name:"HIGH",data:high}] };
    }
    return null;
  }

  function parseTopCwe(j){
    if (j?.charts?.top_cwe?.series) return j.charts.top_cwe.series;
    if (j?.top_cwe?.labels && j?.top_cwe?.values) return j.top_cwe;
    if (Array.isArray(j?.top_cwe_exposure)){
      return { labels: j.top_cwe_exposure.map(x=>x.cwe), values: j.top_cwe_exposure.map(x=>x.count) };
    }
    return { labels: [], values: [] };
  }

  function safeDestroy(k){
    try{ window[k] && window[k].destroy && window[k].destroy(); }catch(e){}
    window[k] = null;
  }

  function render(){
    if (!window.Chart) { console.warn("[VSP][DASH][V6] Chart.js missing"); return; }
    getRid().then(async (rid)=>{
      if (!rid) return;
      const r = await fetch("/api/vsp/dash_charts?rid=" + encodeURIComponent(rid), {cache:"no-store"});
      const j = await r.json();

      // 1) donut severity -> vsp-chart-severity
      const donut = parseDonut(j);
      const cDonut = ensureCanvas("vsp-chart-severity");
      if (cDonut && donut){
        safeDestroy("__VSP_DONUT_V6");
        window.__VSP_DONUT_V6 = new Chart(cDonut, {
          type: "doughnut",
          data: { labels: donut.labels, datasets: [{ data: donut.values }] },
          options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } } }
        });
      }

      // 2) findings trend -> vsp-chart-trend
      const tr = parseTrend(j);
      const cTrend = ensureCanvas("vsp-chart-trend");
      if (cTrend && tr){
        safeDestroy("__VSP_TREND_V6");
        window.__VSP_TREND_V6 = new Chart(cTrend, {
          type: "line",
          data: { labels: tr.labels, datasets: [{ data: tr.values }] },
          options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } } }
        });
      }

      // 3) crit/high by tool -> vsp-chart-bytool
      const bar = parseBarCritHigh(j);
      const cBar = ensureCanvas("vsp-chart-bytool");
      if (cBar && bar){
        const s0 = bar.series?.[0]?.data || [];
        const s1 = bar.series?.[1]?.data || [];
        safeDestroy("__VSP_BYTOOL_V6");
        window.__VSP_BYTOOL_V6 = new Chart(cBar, {
          type: "bar",
          data: { labels: bar.labels, datasets: [{ label:"CRITICAL", data:s0 }, { label:"HIGH", data:s1 }] },
          options: { responsive:true, maintainAspectRatio:false }
        });
      }

      // 4) top cwe -> vsp-chart-topcwe
      const top = parseTopCwe(j);
      const cTop = ensureCanvas("vsp-chart-topcwe");
      if (cTop && top){
        safeDestroy("__VSP_TOPCWE_V6");
        window.__VSP_TOPCWE_V6 = new Chart(cTop, {
          type: "bar",
          data: { labels: top.labels, datasets: [{ data: top.values }] },
          options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } } }
        });
      }
    }).catch(e=>console.warn("[VSP][DASH][V6] render failed", e));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", render);
  else render();
})();
"""
p.write_text(s + "\n\n" + blk + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
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
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p'
