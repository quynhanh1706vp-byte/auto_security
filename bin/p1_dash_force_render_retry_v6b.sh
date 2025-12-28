#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# Patch BOTH likely-loaded files to avoid “page không include file”
FILES=(
  "static/js/vsp_charts_live_v2.js"
  "static/js/vsp_dashboard_live_v2.V1_baseline.js"
)

python3 - <<'PY'
from pathlib import Path

MARK="VSP_P1_DASH_RENDER_V6B_RETRY_VSPCHART"
blk = r"""
// VSP_P1_DASH_RENDER_V6B_RETRY_VSPCHART
(function(){
  if (window.__VSP_DASH_RENDER_V6B) return;
  window.__VSP_DASH_RENDER_V6B = true;

  function ensureCanvas(holderId){
    var el = document.getElementById(holderId);
    if (!el) return null;

    var tag = (el.tagName || "").toLowerCase();
    if (tag === "canvas") return el;

    var c = el.querySelector && el.querySelector("canvas");
    if (!c) {
      c = document.createElement("canvas");
      c.style.width = "100%";
      c.style.height = "260px";
      el.innerHTML = "";     // <-- nếu chạy được thì placeholder phải biến mất
      el.appendChild(c);
    }
    return c;
  }

  async function getRid(){
    try{
      var u = new URL(window.location.href);
      var rid = u.searchParams.get("rid");
      if (rid) return rid;
    }catch(e){}
    try{
      var r = await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
      var j = await r.json();
      if (j && j.items && j.items[0] && j.items[0].run_id) return j.items[0].run_id;
    }catch(e){}
    return "";
  }

  function parseDonut(j){
    if (j && j.charts && j.charts.severity && j.charts.severity.donut) return j.charts.severity.donut;
    if (j && j.donut && j.donut.labels && j.donut.values) return j.donut;
    if (j && Array.isArray(j.severity_distribution)){
      return { labels: j.severity_distribution.map(x=>x.sev), values: j.severity_distribution.map(x=>x.count) };
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
      var labels = j.critical_high_by_tool.map(x=>x.tool);
      var crit = j.critical_high_by_tool.map(x=>x.critical||0);
      var high = j.critical_high_by_tool.map(x=>x.high||0);
      return { labels: labels, series: [{name:"CRITICAL",data:crit},{name:"HIGH",data:high}] };
    }
    return null;
  }
  function parseTopCwe(j){
    if (j && j.charts && j.charts.top_cwe && j.charts.top_cwe.series) return j.charts.top_cwe.series;
    if (j && j.top_cwe && j.top_cwe.labels && j.top_cwe.values) return j.top_cwe;
    if (j && Array.isArray(j.top_cwe_exposure)){
      return { labels: j.top_cwe_exposure.map(x=>x.cwe), values: j.top_cwe_exposure.map(x=>x.count) };
    }
    return { labels: [], values: [] };
  }

  function destroyKey(k){
    try{ if (window[k] && window[k].destroy) window[k].destroy(); }catch(e){}
    window[k]=null;
  }

  async function tryRenderOnce(){
    // must have chart + containers
    if (!window.Chart) return false;

    var a = document.getElementById("vsp-chart-severity");
    var b = document.getElementById("vsp-chart-trend");
    var c = document.getElementById("vsp-chart-bytool");
    var d = document.getElementById("vsp-chart-topcwe");
    if (!a || !b || !c || !d) return false;

    var rid = await getRid();
    if (!rid) return false;

    var resp = await fetch("/api/vsp/dash_charts?rid=" + encodeURIComponent(rid), {cache:"no-store"});
    var j = await resp.json();

    var donut = parseDonut(j);
    var trend = parseTrend(j);
    var bar = parseBarCritHigh(j);
    var top = parseTopCwe(j);

    // render 4
    var c1 = ensureCanvas("vsp-chart-severity");
    if (c1 && donut){
      destroyKey("__VSP_DONUT_V6B");
      window.__VSP_DONUT_V6B = new Chart(c1, { type:"doughnut",
        data:{ labels: donut.labels, datasets:[{data:donut.values}] },
        options:{ responsive:true, maintainAspectRatio:false, plugins:{ legend:{display:false}} }
      });
    }

    var c2 = ensureCanvas("vsp-chart-trend");
    if (c2 && trend){
      destroyKey("__VSP_TREND_V6B");
      window.__VSP_TREND_V6B = new Chart(c2, { type:"line",
        data:{ labels: trend.labels, datasets:[{data:trend.values}] },
        options:{ responsive:true, maintainAspectRatio:false, plugins:{ legend:{display:false}} }
      });
    }

    var c3 = ensureCanvas("vsp-chart-bytool");
    if (c3 && bar){
      destroyKey("__VSP_BYTOOL_V6B");
      var s0 = (bar.series && bar.series[0] && bar.series[0].data) ? bar.series[0].data : [];
      var s1 = (bar.series && bar.series[1] && bar.series[1].data) ? bar.series[1].data : [];
      window.__VSP_BYTOOL_V6B = new Chart(c3, { type:"bar",
        data:{ labels: bar.labels, datasets:[{label:"CRITICAL",data:s0},{label:"HIGH",data:s1}] },
        options:{ responsive:true, maintainAspectRatio:false }
      });
    }

    var c4 = ensureCanvas("vsp-chart-topcwe");
    if (c4 && top){
      destroyKey("__VSP_TOPCWE_V6B");
      window.__VSP_TOPCWE_V6B = new Chart(c4, { type:"bar",
        data:{ labels: top.labels, datasets:[{data:top.values}] },
        options:{ responsive:true, maintainAspectRatio:false, plugins:{ legend:{display:false}} }
      });
    }

    console.log("[VSP][DASH][V6B] rendered rid=", rid);
    return true;
  }

  // retry loop (for late Chart.js load or dynamic DOM)
  var tries = 0;
  var timer = setInterval(function(){
    tries++;
    tryRenderOnce().then(function(ok){
      if (ok || tries >= 20){
        clearInterval(timer);
        if (!ok) console.warn("[VSP][DASH][V6B] gave up after tries=", tries, " (check if Chart.js loaded + containers exist)");
      }
    }).catch(function(e){
      // keep retrying a few times
      if (tries >= 20){
        clearInterval(timer);
        console.warn("[VSP][DASH][V6B] error:", e);
      }
    });
  }, 500);
})();
"""

def patch(fp: Path):
    if not fp.exists():
        return ("missing", str(fp))
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return ("already", str(fp))
    fp.write_text(s + "\n\n" + blk + "\n", encoding="utf-8")
    return ("patched", str(fp))

for f in [Path(x) for x in ("static/js/vsp_charts_live_v2.js","static/js/vsp_dashboard_live_v2.V1_baseline.js")]:
    st, name = patch(f)
    print(f"[{st}] {name}")
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
