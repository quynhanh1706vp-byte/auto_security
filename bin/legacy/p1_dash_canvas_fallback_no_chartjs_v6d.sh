#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_canvas_v6d_${TS}"
echo "[BACKUP] ${JS}.bak_dash_canvas_v6d_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_CANVAS_FALLBACK_V6D"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

blk=r"""
// VSP_P1_DASH_CANVAS_FALLBACK_V6D
(function(){
  if (window.__VSP_DASH_RENDER_V6D) return;
  window.__VSP_DASH_RENDER_V6D = true;

  function ensureCanvas(holderId){
    var el = document.getElementById(holderId);
    if (!el) return null;
    var tag = (el.tagName||"").toLowerCase();
    if (tag === "canvas") return el;

    var c = el.querySelector && el.querySelector("canvas");
    if (!c){
      c = document.createElement("canvas");
      c.width = 900; c.height = 300;
      c.style.width="100%";
      c.style.height="260px";
      el.innerHTML=""; // clear placeholder
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
      var labels = j.critical_high_by_tool.map(x=>x.tool);
      var crit = j.critical_high_by_tool.map(x=>x.critical||0);
      var high = j.critical_high_by_tool.map(x=>x.high||0);
      return { labels: labels, series: [{name:"CRITICAL",data:crit},{name:"HIGH",data:high}] };
    }
    return null;
  }
  function parseTopCwe(j){
    if (j?.charts?.top_cwe?.series) return j.charts.top_cwe.series;
    if (j?.top_cwe?.labels && j?.top_cwe?.values) return j.top_cwe;
    if (Array.isArray(j?.top_cwe_exposure))
      return { labels: j.top_cwe_exposure.map(x=>x.cwe), values: j.top_cwe_exposure.map(x=>x.count) };
    return { labels: [], values: [] };
  }

  // ---- Canvas drawing helpers (no Chart.js) ----
  function ctx2d(canvas){
    var ctx = canvas.getContext("2d");
    var w = canvas.width, h = canvas.height;
    // handle hiDPI
    var dpr = window.devicePixelRatio || 1;
    var cssW = canvas.clientWidth || w;
    var cssH = canvas.clientHeight || h;
    canvas.width = Math.max(300, Math.floor(cssW * dpr));
    canvas.height = Math.max(200, Math.floor(cssH * dpr));
    ctx.setTransform(dpr,0,0,dpr,0,0);
    return ctx;
  }

  function clear(ctx, w, h){
    ctx.clearRect(0,0,w,h);
    // subtle grid bg
    ctx.globalAlpha = 0.08;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0,0,w,h);
    ctx.globalAlpha = 1;
  }

  function textCenter(ctx, w, h, msg){
    ctx.save();
    ctx.fillStyle = "rgba(255,255,255,0.75)";
    ctx.font = "12px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(msg, w/2, h/2);
    ctx.restore();
  }

  function drawDonut(canvas, labels, values){
    var ctx = ctx2d(canvas);
    var w = canvas.clientWidth || 900, h = canvas.clientHeight || 260;
    clear(ctx, w, h);
    var total = values.reduce((a,b)=>a+(+b||0),0);
    if (!total){ textCenter(ctx,w,h,"No data"); return; }

    var cx=w/2, cy=h/2, r=Math.min(w,h)*0.32, rIn=r*0.55;
    var ang=-Math.PI/2;

    var palette=["#ef4444","#f59e0b","#3b82f6","#22c55e","#a855f7","#94a3b8"];
    for (var i=0;i<values.length;i++){
      var v=+values[i]||0;
      var a=(v/total)*Math.PI*2;
      ctx.beginPath();
      ctx.moveTo(cx,cy);
      ctx.fillStyle=palette[i%palette.length];
      ctx.globalAlpha=0.85;
      ctx.arc(cx,cy,r,ang,ang+a);
      ctx.closePath();
      ctx.fill();
      ang+=a;
    }
    // hole
    ctx.globalAlpha=1;
    ctx.beginPath();
    ctx.fillStyle="rgba(0,0,0,0.55)";
    ctx.arc(cx,cy,rIn,0,Math.PI*2);
    ctx.fill();

    // center text
    ctx.fillStyle="rgba(255,255,255,0.85)";
    ctx.font="bold 16px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.textAlign="center"; ctx.textBaseline="middle";
    ctx.fillText(String(total), cx, cy-2);
    ctx.font="12px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.fillStyle="rgba(255,255,255,0.7)";
    ctx.fillText("total", cx, cy+16);
  }

  function drawLine(canvas, labels, values){
    var ctx = ctx2d(canvas);
    var w = canvas.clientWidth || 900, h = canvas.clientHeight || 260;
    clear(ctx, w, h);
    if (!values || !values.length){ textCenter(ctx,w,h,"No data"); return; }

    var padL=46, padR=14, padT=14, padB=30;
    var plotW=w-padL-padR, plotH=h-padT-padB;

    var maxV=Math.max.apply(null, values.map(v=>+v||0));
    var minV=Math.min.apply(null, values.map(v=>+v||0));
    if (maxV===minV) maxV=minV+1;

    // axes
    ctx.strokeStyle="rgba(255,255,255,0.18)";
    ctx.lineWidth=1;
    ctx.beginPath();
    ctx.moveTo(padL,padT);
    ctx.lineTo(padL,padT+plotH);
    ctx.lineTo(padL+plotW,padT+plotH);
    ctx.stroke();

    // line
    ctx.strokeStyle="rgba(59,130,246,0.9)";
    ctx.lineWidth=2;
    ctx.beginPath();
    for (var i=0;i<values.length;i++){
      var x = padL + (i/(Math.max(1,values.length-1)))*plotW;
      var y = padT + (1-((+values[i]||0)-minV)/(maxV-minV))*plotH;
      if (i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
    }
    ctx.stroke();

    // points
    ctx.fillStyle="rgba(59,130,246,0.95)";
    for (var i=0;i<values.length;i++){
      var x = padL + (i/(Math.max(1,values.length-1)))*plotW;
      var y = padT + (1-((+values[i]||0)-minV)/(maxV-minV))*plotH;
      ctx.beginPath(); ctx.arc(x,y,3,0,Math.PI*2); ctx.fill();
    }

    // y labels
    ctx.fillStyle="rgba(255,255,255,0.7)";
    ctx.font="12px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.textAlign="right"; ctx.textBaseline="middle";
    ctx.fillText(String(maxV), padL-8, padT);
    ctx.fillText(String(minV), padL-8, padT+plotH);
  }

  function drawBars(canvas, labels, s0, s1){
    var ctx = ctx2d(canvas);
    var w = canvas.clientWidth || 900, h = canvas.clientHeight || 260;
    clear(ctx, w, h);
    if (!labels || !labels.length){ textCenter(ctx,w,h,"No data"); return; }

    var padL=46, padR=14, padT=14, padB=30;
    var plotW=w-padL-padR, plotH=h-padT-padB;

    var maxV=0;
    for (var i=0;i<labels.length;i++){
      maxV=Math.max(maxV, (+s0[i]||0)+(+s1[i]||0), (+s0[i]||0), (+s1[i]||0));
    }
    if (!maxV) maxV=1;

    // axes
    ctx.strokeStyle="rgba(255,255,255,0.18)";
    ctx.lineWidth=1;
    ctx.beginPath();
    ctx.moveTo(padL,padT);
    ctx.lineTo(padL,padT+plotH);
    ctx.lineTo(padL+plotW,padT+plotH);
    ctx.stroke();

    var n=labels.length;
    var groupW = plotW / n;
    var barW = Math.max(6, groupW*0.28);

    for (var i=0;i<n;i++){
      var x0 = padL + i*groupW + groupW*0.18;
      var v0 = +s0[i]||0;
      var v1 = +s1[i]||0;

      var h0 = (v0/maxV)*plotH;
      var h1 = (v1/maxV)*plotH;

      // critical
      ctx.fillStyle="rgba(239,68,68,0.85)";
      ctx.fillRect(x0, padT+plotH-h0, barW, h0);

      // high (next to)
      ctx.fillStyle="rgba(245,158,11,0.85)";
      ctx.fillRect(x0+barW+4, padT+plotH-h1, barW, h1);
    }
  }

  async function renderOnce(){
    var a=document.getElementById("vsp-chart-severity");
    var b=document.getElementById("vsp-chart-trend");
    var c=document.getElementById("vsp-chart-bytool");
    var d=document.getElementById("vsp-chart-topcwe");
    if (!a || !b || !c || !d) return false;

    var rid = await getRid();
    if (!rid) return false;

    var resp = await fetch("/api/vsp/dash_charts?rid="+encodeURIComponent(rid), {cache:"no-store"});
    var j = await resp.json();

    var donut=parseDonut(j);
    var trend=parseTrend(j);
    var bar=parseBarCritHigh(j);
    var top=parseTopCwe(j);

    // DONUT
    var c1=ensureCanvas("vsp-chart-severity");
    if (c1 && donut) drawDonut(c1, donut.labels||[], donut.values||[]);

    // TREND
    var c2=ensureCanvas("vsp-chart-trend");
    if (c2 && trend) drawLine(c2, trend.labels||[], trend.values||[]);

    // BYTOOL
    var c3=ensureCanvas("vsp-chart-bytool");
    if (c3 && bar){
      var s0 = bar.series?.[0]?.data || [];
      var s1 = bar.series?.[1]?.data || [];
      drawBars(c3, bar.labels||[], s0, s1);
    }

    // TOPCWE (single series)
    var c4=ensureCanvas("vsp-chart-topcwe");
    if (c4 && top){
      drawBars(c4, top.labels||[], top.values||[], new Array((top.labels||[]).length).fill(0));
    }

    console.log("[VSP][DASH][V6D] canvas-rendered rid=", rid, "ChartJS=", !!window.Chart);
    return true;
  }

  var tries=0;
  var t=setInterval(function(){
    tries++;
    renderOnce().then(function(ok){
      if (ok || tries>=20){
        clearInterval(t);
        if (!ok) console.warn("[VSP][DASH][V6D] gave up: containers/rid missing");
      }
    }).catch(function(e){
      if (tries>=20){ clearInterval(t); console.warn("[VSP][DASH][V6D] error", e); }
    });
  }, 500);
})();
"""
p.write_text(s + "\n\n" + blk + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
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
