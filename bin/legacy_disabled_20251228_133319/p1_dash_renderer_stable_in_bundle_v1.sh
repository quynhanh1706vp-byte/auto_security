#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need sed; need awk; need ss; need curl; need python3

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_stable_${TS}"
echo "[BACKUP] ${JS}.bak_dash_stable_${TS}"

# tránh chồng marker nhiều lần
if grep -q "VSP_P1_DASH_RENDER_STABLE_V1" "$JS"; then
  echo "[OK] marker already present; skip inject"
else
  cat >> "$JS" <<'JSX'

/* ===== VSP_P1_DASH_RENDER_STABLE_V1 (NO Chart.js) ===== */
(function(){
  const LOGP = "[VSP][DASH][STABLE_V1]";
  const $ = (id)=>document.getElementById(id);
  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));
  const now = ()=>Date.now();

  function onReady(fn){
    if (document.readyState === "complete" || document.readyState === "interactive") return fn();
    document.addEventListener("DOMContentLoaded", fn, {once:true});
  }

  async function fetchJSON(url){
    const u = url + (url.includes("?") ? "&" : "?") + "_=" + now();
    const r = await fetch(u, {cache:"no-store", credentials:"same-origin"});
    const t = await r.text();
    try { return JSON.parse(t); } catch(e){
      console.warn(LOGP, "bad json from", u, "len=", (t||"").length);
      throw e;
    }
  }

  function fitCanvas(canvas, w, h){
    const dpr = window.devicePixelRatio || 1;
    canvas.width  = Math.max(10, Math.floor(w * dpr));
    canvas.height = Math.max(10, Math.floor(h * dpr));
    canvas.style.width  = Math.max(10, Math.floor(w)) + "px";
    canvas.style.height = Math.max(10, Math.floor(h)) + "px";
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr,0,0,dpr,0,0);
    return ctx;
  }

  function ensureCanvasIn(containerId, minH){
    const box = $(containerId);
    if (!box) return null;
    box.textContent = ""; // clear placeholder
    const c = document.createElement("canvas");
    c.setAttribute("aria-label", containerId);
    c.style.display = "block";
    c.style.width = "100%";
    c.style.height = (minH||220) + "px";
    box.appendChild(c);

    const w = box.clientWidth || 800;
    const h = Math.max(minH||220, box.clientHeight || 0, 200);
    const ctx = fitCanvas(c, w, h);
    return {box, canvas:c, ctx, w, h};
  }

  function drawTextCenter(ctx, w, h, txt){
    ctx.clearRect(0,0,w,h);
    ctx.globalAlpha = 1;
    ctx.font = "13px sans-serif";
    ctx.fillStyle = "rgba(220,230,255,0.75)";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(txt, w/2, h/2);
  }

  function drawDonut(ctx, w, h, items){
    // items: [{sev,count}]
    const total = items.reduce((a,x)=>a+(+x.count||0),0) || 1;
    const cx=w/2, cy=h/2, r=Math.min(w,h)*0.32;
    const r2=r*0.62;
    let a0 = -Math.PI/2;

    ctx.clearRect(0,0,w,h);
    ctx.lineWidth = 18;
    const palette = [
      "rgba(255,80,80,0.85)",   // CRITICAL
      "rgba(255,160,80,0.85)",  // HIGH
      "rgba(255,220,80,0.85)",  // MEDIUM
      "rgba(160,220,120,0.85)", // LOW
      "rgba(120,180,255,0.85)", // INFO
      "rgba(180,180,200,0.65)"  // TRACE
    ];
    items.forEach((it, i)=>{
      const v = (+it.count||0);
      const a1 = a0 + (v/total)*Math.PI*2;
      ctx.beginPath();
      ctx.strokeStyle = palette[i % palette.length];
      ctx.arc(cx,cy,r,a0,a1,false);
      ctx.stroke();
      a0 = a1;
    });

    // hole
    ctx.globalCompositeOperation = "destination-out";
    ctx.beginPath();
    ctx.arc(cx,cy,r2,0,Math.PI*2);
    ctx.fill();
    ctx.globalCompositeOperation = "source-over";

    // center text
    ctx.font="12px sans-serif";
    ctx.fillStyle="rgba(220,230,255,0.85)";
    ctx.textAlign="center";
    ctx.textBaseline="middle";
    ctx.fillText("TOTAL", cx, cy-8);
    ctx.font="14px sans-serif";
    ctx.fillText(String(total), cx, cy+10);
  }

  function drawBars(ctx, w, h, rows, keyA, keyB){
    // rows: [{tool, critical, high}] -> stacked bar
    ctx.clearRect(0,0,w,h);
    const pad=18, left=80, top=14, bottom=24;
    const innerW = w-left-pad, innerH = h-top-bottom;

    const maxV = Math.max(1, ...rows.map(r=>(+r[keyA]||0)+(+r[keyB]||0)));
    ctx.font="12px sans-serif";
    ctx.textBaseline="middle";

    rows.slice(0,8).forEach((r, idx)=>{
      const y = top + idx*(innerH/8) + (innerH/8)/2;
      const total = (+r[keyA]||0)+(+r[keyB]||0);
      const bw = (total/maxV)*innerW;

      // label
      ctx.fillStyle="rgba(220,230,255,0.75)";
      ctx.textAlign="right";
      ctx.fillText(String(r.tool||"").slice(0,10), left-8, y);

      // bar
      ctx.fillStyle="rgba(255,120,120,0.75)";
      ctx.fillRect(left, y-7, Math.max(2,bw), 14);

      // value
      ctx.textAlign="left";
      ctx.fillStyle="rgba(220,230,255,0.65)";
      ctx.fillText(String(total), left + Math.max(2,bw) + 6, y);
    });
  }

  function drawTopCWE(ctx, w, h, rows){
    // rows: [{cwe,count}]
    ctx.clearRect(0,0,w,h);
    const pad=18, left=90, top=14, bottom=22;
    const innerW=w-left-pad, innerH=h-top-bottom;

    const maxV = Math.max(1, ...rows.map(r=>(+r.count||0)));
    ctx.font="12px sans-serif";
    rows.slice(0,8).forEach((r, idx)=>{
      const y = top + idx*(innerH/8) + 6;
      const bw = ((+r.count||0)/maxV)*innerW;

      ctx.fillStyle="rgba(220,230,255,0.75)";
      ctx.textAlign="right";
      ctx.fillText(String(r.cwe||"").slice(0,14), left-8, y+6);

      ctx.fillStyle="rgba(120,180,255,0.65)";
      ctx.fillRect(left, y, Math.max(2,bw), 12);

      ctx.textAlign="left";
      ctx.fillStyle="rgba(220,230,255,0.6)";
      ctx.fillText(String(+r.count||0), left + Math.max(2,bw) + 6, y+6);
    });
  }

  function drawTrend(ctx, w, h, points){
    // points: [{rid,total_findings}] (càng mới càng phải)
    ctx.clearRect(0,0,w,h);
    const pad=18, left=40, top=14, bottom=28;
    const innerW=w-left-pad, innerH=h-top-bottom;

    const ys = points.map(p=>(+p.total_findings||0));
    const maxY = Math.max(1, ...ys);
    const minY = Math.min(...ys, 0);

    // axes
    ctx.strokeStyle="rgba(220,230,255,0.18)";
    ctx.beginPath();
    ctx.moveTo(left, top);
    ctx.lineTo(left, top+innerH);
    ctx.lineTo(left+innerW, top+innerH);
    ctx.stroke();

    if(points.length < 2){
      drawTextCenter(ctx,w,h,"trend: not enough points");
      return;
    }

    // line
    ctx.strokeStyle="rgba(160,220,120,0.85)";
    ctx.lineWidth=2;
    ctx.beginPath();
    points.forEach((p,i)=>{
      const x = left + (i/(points.length-1))*innerW;
      const yv = (+p.total_findings||0);
      const y = top + innerH - ((yv-minY)/(maxY-minY||1))*innerH;
      if(i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
    });
    ctx.stroke();
  }

  function setText(id, val){
    const el=$(id);
    if(!el) return;
    el.textContent = (val===null || val===undefined) ? "N/A" : String(val);
  }

  function setGate(id, overall){
    const el=$(id);
    if(!el) return;
    const s = String(overall||"").toUpperCase();
    el.textContent = (s || "N/A") + (s==="RED" ? " • Blocking pipeline" : "");
    el.classList.remove("vsp-gate-red","vsp-gate-amber","vsp-gate-green");
    if(s==="RED") el.classList.add("vsp-gate-red");
    else if(s==="AMBER") el.classList.add("vsp-gate-amber");
    else if(s==="GREEN") el.classList.add("vsp-gate-green");
  }

  async function resolveRidLatest(){
    const j = await fetchJSON("/api/vsp/runs?limit=1");
    return (j && (j.rid_latest || (j.items && j.items[0] && j.items[0].run_id))) || null;
  }

  async function runOnce(){
    // đảm bảo containers có mặt
    const ids = ["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcwe"];
    const miss = ids.filter(x=>!$(x));
    if(miss.length){
      console.warn(LOGP, "missing containers:", miss.join(","));
      return;
    }

    const rid = await resolveRidLatest();
    setText("vsp-header-run-id", rid || "N/A");
    setText("vsp_live_rid", "rid_latest: " + (rid||"N/A"));

    if(!rid){
      console.warn(LOGP, "rid_latest N/A");
      return;
    }

    const kpis = await fetchJSON("/api/vsp/dash_kpis?rid=" + encodeURIComponent(rid));
    const charts = await fetchJSON("/api/vsp/dash_charts?rid=" + encodeURIComponent(rid));

    // KPI mapping
    setText("vsp-kpi-total-findings", kpis.total_findings);
    setText("vsp-kpi-critical", (kpis.counts_total && kpis.counts_total.CRITICAL));
    setText("vsp-kpi-high",     (kpis.counts_total && kpis.counts_total.HIGH));
    setText("vsp-kpi-medium",   (kpis.counts_total && kpis.counts_total.MEDIUM));
    setText("vsp-kpi-low",      (kpis.counts_total && kpis.counts_total.LOW));
    setText("vsp-kpi-score",    kpis.security_score);
    setText("vsp-kpi-top-tool", kpis.top_risky_tool);
    setText("vsp-kpi-top-cwe",  kpis.top_impacted_cwe);
    setText("vsp-kpi-top-module", kpis.top_vulnerable_module);
    setGate("vsp-kpi-ci-gate", kpis.overall);

    // charts
    const sevBox = ensureCanvasIn("vsp-chart-severity", 220);
    if(sevBox) drawDonut(sevBox.ctx, sevBox.w, sevBox.h, (charts.severity_distribution||[]));

    const trBox = ensureCanvasIn("vsp-chart-trend", 220);
    if(trBox) drawTrend(trBox.ctx, trBox.w, trBox.h, (charts.findings_trend||[]));

    const btBox = ensureCanvasIn("vsp-chart-bytool", 220);
    if(btBox) drawBars(btBox.ctx, btBox.w, btBox.h, (charts.critical_high_by_tool||[]), "critical", "high");

    const cweBox = ensureCanvasIn("vsp-chart-topcwe", 220);
    if(cweBox) drawTopCWE(cweBox.ctx, cweBox.w, cweBox.h, (charts.top_cwe_exposure||[]));

    console.log(LOGP, "rendered OK rid=", rid);
  }

  async function runWithRetry(){
    // Retry vài lần vì bundle có thể chạy trước khi DOM layout ổn định
    for(let i=0;i<8;i++){
      try{
        await runOnce();
        return;
      }catch(e){
        console.warn(LOGP, "retry", i, e && e.message ? e.message : e);
        await sleep(250);
      }
    }
    console.warn(LOGP, "gave up after retries");
  }

  onReady(()=>{ setTimeout(runWithRetry, 0); });
})();
JSX
  echo "[OK] injected: VSP_P1_DASH_RENDER_STABLE_V1"
fi

echo "== restart clean :8910 (nohup only) =="
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true
rm -f /tmp/vsp_ui_8910.lock || true
: > out_ci/ui_8910.boot.log || true

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 0.9

echo "== verify endpoints =="
BASE=http://127.0.0.1:8910
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json; j=json.load(sys.stdin); print(j.get('rid_latest') or j['items'][0]['run_id'])")"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 240; echo
curl -sS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 240; echo
curl -sS "$BASE/static/js/vsp_bundle_commercial_v2.js" | grep -n "VSP_P1_DASH_RENDER_STABLE_V1" | head
curl -sS -I "$BASE/vsp5" | sed -n '1,10p'
