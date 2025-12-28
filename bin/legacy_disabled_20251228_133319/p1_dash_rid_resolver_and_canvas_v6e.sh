#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need curl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_v6e_${TS}"
echo "[BACKUP] ${JS}.bak_dash_v6e_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_RID_RESOLVER_CANVAS_V6E"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

blk=r"""
// VSP_P1_DASH_RID_RESOLVER_CANVAS_V6E
(function(){
  if (window.__VSP_DASH_V6E) return;
  window.__VSP_DASH_V6E = true;

  function qs(id){ return document.getElementById(id); }

  function ensureCanvas(holderId){
    var el = qs(holderId);
    if (!el) return null;
    if ((el.tagName||"").toLowerCase()==="canvas") return el;
    var c = el.querySelector && el.querySelector("canvas");
    if (!c){
      c=document.createElement("canvas");
      c.style.width="100%";
      c.style.height="260px";
      el.innerHTML="";
      el.appendChild(c);
    }
    return c;
  }

  function setupCtx(canvas){
    var ctx=canvas.getContext("2d");
    var dpr=window.devicePixelRatio||1;
    var w=Math.max(320, canvas.clientWidth||900);
    var h=Math.max(220, canvas.clientHeight||260);
    canvas.width=Math.floor(w*dpr);
    canvas.height=Math.floor(h*dpr);
    ctx.setTransform(dpr,0,0,dpr,0,0);
    return {ctx,w,h};
  }

  function clearBg(ctx,w,h){
    ctx.clearRect(0,0,w,h);
    ctx.fillStyle="rgba(255,255,255,0.03)";
    ctx.fillRect(0,0,w,h);
  }

  function drawText(ctx,w,h,msg){
    ctx.fillStyle="rgba(255,255,255,0.75)";
    ctx.font="12px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.textAlign="center"; ctx.textBaseline="middle";
    ctx.fillText(msg, w/2, h/2);
  }

  function drawDonut(canvas, labels, values){
    var o=setupCtx(canvas), ctx=o.ctx, w=o.w, h=o.h;
    clearBg(ctx,w,h);
    var total=(values||[]).reduce((a,b)=>a+(+b||0),0);
    if (!total){ drawText(ctx,w,h,"No data"); return; }
    var cx=w/2, cy=h/2, r=Math.min(w,h)*0.32, rIn=r*0.55;
    var ang=-Math.PI/2;
    var pal=["#ef4444","#f59e0b","#3b82f6","#22c55e","#a855f7","#94a3b8"];
    for (var i=0;i<values.length;i++){
      var v=+values[i]||0, a=(v/total)*Math.PI*2;
      ctx.beginPath(); ctx.moveTo(cx,cy);
      ctx.fillStyle=pal[i%pal.length];
      ctx.globalAlpha=0.85;
      ctx.arc(cx,cy,r,ang,ang+a);
      ctx.closePath(); ctx.fill();
      ang+=a;
    }
    ctx.globalAlpha=1;
    ctx.beginPath(); ctx.fillStyle="rgba(0,0,0,0.55)";
    ctx.arc(cx,cy,rIn,0,Math.PI*2); ctx.fill();
    ctx.fillStyle="rgba(255,255,255,0.85)";
    ctx.font="bold 16px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.textAlign="center"; ctx.textBaseline="middle";
    ctx.fillText(String(total), cx, cy-2);
    ctx.font="12px system-ui, -apple-system, Segoe UI, Roboto, Arial";
    ctx.fillStyle="rgba(255,255,255,0.65)";
    ctx.fillText("total", cx, cy+16);
  }

  function drawLine(canvas, labels, values){
    var o=setupCtx(canvas), ctx=o.ctx, w=o.w, h=o.h;
    clearBg(ctx,w,h);
    if (!values || !values.length){ drawText(ctx,w,h,"No data"); return; }
    var padL=46,padR=14,padT=14,padB=30;
    var pw=w-padL-padR, ph=h-padT-padB;
    var maxV=Math.max.apply(null, values.map(v=>+v||0));
    var minV=Math.min.apply(null, values.map(v=>+v||0));
    if (maxV===minV) maxV=minV+1;

    ctx.strokeStyle="rgba(255,255,255,0.18)";
    ctx.lineWidth=1;
    ctx.beginPath();
    ctx.moveTo(padL,padT);
    ctx.lineTo(padL,padT+ph);
    ctx.lineTo(padL+pw,padT+ph);
    ctx.stroke();

    ctx.strokeStyle="rgba(59,130,246,0.9)";
    ctx.lineWidth=2;
    ctx.beginPath();
    for (var i=0;i<values.length;i++){
      var x=padL+(i/(Math.max(1,values.length-1)))*pw;
      var y=padT+(1-((+values[i]||0)-minV)/(maxV-minV))*ph;
      if (i===0) ctx.moveTo(x,y); else ctx.lineTo(x,y);
    }
    ctx.stroke();
  }

  function drawBars(canvas, labels, a0, a1){
    var o=setupCtx(canvas), ctx=o.ctx, w=o.w, h=o.h;
    clearBg(ctx,w,h);
    if (!labels || !labels.length){ drawText(ctx,w,h,"No data"); return; }
    var padL=46,padR=14,padT=14,padB=30;
    var pw=w-padL-padR, ph=h-padT-padB;
    var maxV=1;
    for (var i=0;i<labels.length;i++){
      maxV=Math.max(maxV, (+a0[i]||0), (+a1[i]||0), (+a0[i]||0)+(+a1[i]||0));
    }

    ctx.strokeStyle="rgba(255,255,255,0.18)";
    ctx.lineWidth=1;
    ctx.beginPath();
    ctx.moveTo(padL,padT);
    ctx.lineTo(padL,padT+ph);
    ctx.lineTo(padL+pw,padT+ph);
    ctx.stroke();

    var n=labels.length;
    var gw=pw/n;
    var bw=Math.max(6, gw*0.28);
    for (var i=0;i<n;i++){
      var x0=padL+i*gw+gw*0.18;
      var v0=+a0[i]||0, v1=+a1[i]||0;
      var h0=(v0/maxV)*ph, h1=(v1/maxV)*ph;
      ctx.fillStyle="rgba(239,68,68,0.85)";
      ctx.fillRect(x0, padT+ph-h0, bw, h0);
      ctx.fillStyle="rgba(245,158,11,0.85)";
      ctx.fillRect(x0+bw+4, padT+ph-h1, bw, h1);
    }
  }

  function parse(j){
    var donut=null, trend=null, bar=null, top=null;

    if (Array.isArray(j?.severity_distribution))
      donut={labels:j.severity_distribution.map(x=>x.sev), values:j.severity_distribution.map(x=>x.count)};

    if (Array.isArray(j?.findings_trend))
      trend={labels:j.findings_trend.map(x=>x.rid), values:j.findings_trend.map(x=>x.total)};

    if (Array.isArray(j?.critical_high_by_tool)){
      bar={labels:j.critical_high_by_tool.map(x=>x.tool),
           s0:j.critical_high_by_tool.map(x=>x.critical||0),
           s1:j.critical_high_by_tool.map(x=>x.high||0)};
    }

    if (Array.isArray(j?.top_cwe_exposure))
      top={labels:j.top_cwe_exposure.map(x=>x.cwe), values:j.top_cwe_exposure.map(x=>x.count)};

    return {donut,trend,bar,top};
  }

  function ridFromText(){
    try{
      var t=(document.body && (document.body.innerText||document.body.textContent)||"");
      var m=t.match(/rid_latest\s*=\s*([A-Za-z0-9_\-\.]+)/i) || t.match(/rid_latest\s*:\s*([A-Za-z0-9_\-\.]+)/i);
      return m ? (m[1]||"") : "";
    }catch(e){ return ""; }
  }

  async function resolveRid(){
    // 1) URL param
    try{
      var u=new URL(window.location.href);
      var rid=u.searchParams.get("rid");
      if (rid) return rid;
    }catch(e){}

    // 2) hidden input / element
    var el=qs("vsp_live_rid");
    if (el){
      var v = (el.value!=null ? el.value : "") || (el.textContent||"").trim();
      if (v) return v;
    }

    // 3) text regex (your “OK rid_latest=...”)
    var r3 = ridFromText();
    if (r3) return r3;

    // 4) API fallback
    try{
      var r=await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
      var j=await r.json();
      var rid2=j?.items?.[0]?.run_id || "";
      return rid2;
    }catch(e){
      return "";
    }
  }

  async function render(){
    // only on /vsp5
    if (!(location.pathname||"").includes("/vsp5")) return false;

    var ids=["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcwe"];
    var okIds = ids.every(id=>!!qs(id));
    var rid = await resolveRid();

    console.log("[VSP][DASH][V6E] check ids=", okIds, "rid=", rid);

    if (!okIds || !rid) return false;

    // fetch charts once
    var resp=await fetch("/api/vsp/dash_charts?rid="+encodeURIComponent(rid), {cache:"no-store"});
    var j=await resp.json();
    var o=parse(j);

    var c1=ensureCanvas("vsp-chart-severity"); if (c1 && o.donut) drawDonut(c1, o.donut.labels, o.donut.values);
    var c2=ensureCanvas("vsp-chart-trend"); if (c2 && o.trend) drawLine(c2, o.trend.labels, o.trend.values);
    var c3=ensureCanvas("vsp-chart-bytool"); if (c3 && o.bar) drawBars(c3, o.bar.labels, o.bar.s0, o.bar.s1);
    var c4=ensureCanvas("vsp-chart-topcwe"); if (c4 && o.top) drawBars(c4, o.top.labels, o.top.values, new Array(o.top.labels.length).fill(0));

    console.log("[VSP][DASH][V6E] rendered rid=", rid);
    return true;
  }

  function start(){
    var tries=0;
    var t=setInterval(function(){
      tries++;
      render().then(function(ok){
        if (ok || tries>=60){ // 30s
          clearInterval(t);
          if (!ok) console.warn("[VSP][DASH][V6E] gave up (rid/ids still missing)");
        }
      }).catch(function(e){
        if (tries>=60){ clearInterval(t); console.warn("[VSP][DASH][V6E] error", e); }
      });
    }, 500);
  }

  if (document.readyState==="complete") start();
  else window.addEventListener("load", start);
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
