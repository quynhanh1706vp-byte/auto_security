(function () {
  'use strict';

  const API_URL = '/api/vsp/dashboard_v3_v2';

  function getCanvasForChart(name) {
    // Tìm container có data-chart
    var container = document.querySelector('[data-chart="' + name + '"]');
    if (!container) {
      console.warn('[VSP][CHART] Không tìm thấy container data-chart=' + name);
      return null;
    }

    var canvas = container.querySelector('canvas');
    if (!canvas) {
      canvas = document.createElement('canvas');
      container.appendChild(canvas);
    }
    return canvas;
  }

  function renderSeverityDonut(bySev) {
    if (typeof Chart === 'undefined') {
      console.warn('[VSP][CHART] Chart.js not loaded');
      return;
    }

    var canvas = getCanvasForChart('severity_donut');
    if (!canvas) return;

    var buckets = ['CRITICAL','HIGH','MEDIUM','LOW','INFO', trace:"TRACE"];
    var data = buckets.map(function (k) {
      return Number(bySev && bySev[k] || 0);
    });

    var ctx = canvas.getContext('2d');
    new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: buckets,
        datasets: [{
          data: data
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '70%',
        plugins: {
          legend: { display: false }
        }
      }
    });
  }

  function renderFindingsByTool(byTool) {
    if (typeof Chart === 'undefined') {
      console.warn('[VSP][CHART] Chart.js not loaded');
      return;
    }

    var canvas = getCanvasForChart('findings_by_tool');
    if (!canvas) return;

    var order = ['gitleaks','semgrep','bandit','trivy_fs','grype','kics','codeql','syft'];
    var labels = [];
    var data = [];

    order.forEach(function (key) {
      if (!byTool || byTool[key] === undefined) return;
      labels.push(key);
      data.push(Number(byTool[key] || 0));
    });

    var ctx = canvas.getContext('2d');
    new Chart(ctx, {
      type: 'bar',
      data: {
        labels: labels,
        datasets: [{
          data: data
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: {
          x: { ticks: { autoSkip: false } }
        }
      }
    });
  }

  // Trend Over Time – placeholder: chờ /api/vsp/runs, giờ chỉ hiển thị "No data"
  function renderTrendPlaceholder() {
    var container = document.querySelector('[data-chart="trend_over_time"]');
    if (!container) return;
    container.innerHTML = '<div class="vsp-chart-empty">Trend chart requires /api/vsp/runs data.</div>';
  }

  function loadCharts() {
    fetch(API_URL)
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (!data || data.ok === false) {
          console.warn('[VSP][CHART] /api/vsp/dashboard_v3_v2 not ok:', data);
          return;
        }
        var summary = data.summary || {};
        var bySev  = summary.by_severity || data.severity || {};
        var byTool = summary.by_tool     || data.by_tool   || {};

        renderSeverityDonut(bySev);
        renderFindingsByTool(byTool);
        renderTrendPlaceholder();
      })
      .catch(function (err) {
        console.error('[VSP][CHART] fetch error:', err);
      });
  }

  document.addEventListener('DOMContentLoaded', loadCharts);
})();



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
      const r = await fetch("/api/vsp/rid_latest_v3", {cache:"no-store"});
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
      const r = await fetch("/api/vsp/rid_latest_v3", {cache:"no-store"});
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
      var r = await fetch("/api/vsp/rid_latest_v3", {cache:"no-store"});
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

