#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_runs_reports_overlay_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_kpi_canvas_${TS}"
echo "[BACKUP] ${JS}.bak_fix_kpi_canvas_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_RUNS_KPI_JS_V1" not in s:
    raise SystemExit("[ERR] marker VSP_P2_RUNS_KPI_JS_V1 not found in JS")

# Replace the chunk from function drawStackedBars ... up to async function loadRunsKpi
pat = re.compile(r'function\s+drawStackedBars\s*\([\s\S]*?\n\s*async\s+function\s+loadRunsKpi\s*\(', re.M)

replacement = textwrap.dedent(r"""
function drawStackedBars(canvas, labels, series){
  if(!canvas) return;
  const safeLabels = Array.isArray(labels) ? labels : [];
  const ctx = canvas.getContext("2d");
  const dpr = (window.devicePixelRatio||1);

  const w = canvas.width = Math.max(10, (canvas.clientWidth||600)) * dpr;
  const hh = canvas.getAttribute("height") ? Number(canvas.getAttribute("height")) : 120;
  const h = canvas.height = Math.max(40, hh) * dpr;
  ctx.clearRect(0,0,w,h);

  if(safeLabels.length === 0){
    ctx.globalAlpha = 0.75;
    ctx.fillStyle = "#9fb0c7";
    ctx.font = `${12*dpr}px sans-serif`;
    ctx.fillText("No trend data (0 day)", 12*dpr, 20*dpr);
    ctx.globalAlpha = 1;
    return;
  }

  const padL = 28*dpr, padR = 8*dpr, padT = 10*dpr, padB = 22*dpr;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  const n = safeLabels.length;
  const gap = 2*dpr;
  const barW = Math.max(2*dpr, Math.floor(plotW / n) - gap);

  const totals = safeLabels.map((_,i)=> (series||[]).reduce((a,s)=> a + (Number(s?.values?.[i]||0)), 0));
  const maxT = Math.max(1, ...totals);

  ctx.globalAlpha = 0.5;
  ctx.fillStyle = "#9fb0c7";
  ctx.fillRect(padL, padT+plotH, plotW, 1*dpr);
  ctx.globalAlpha = 1;

  for(let i=0;i<n;i++){
    const x = padL + i*(barW+gap);
    let y = padT + plotH;

    for(const ss of (series||[])){
      const v = Number(ss?.values?.[i]||0);
      if(v<=0) continue;
      const bh = Math.max(1, Math.round((v/maxT)*plotH));
      y -= bh;
      ctx.globalAlpha = ss.alpha || 0.25;
      ctx.fillStyle = "#9fb0c7";
      ctx.fillRect(x, y, barW, bh);
    }
    ctx.globalAlpha = 1;

    if(i===0 || i===n-1 || n<=14 || (i%Math.ceil(n/6)===0)){
      ctx.globalAlpha = 0.7;
      ctx.fillStyle = "#9fb0c7";
      ctx.font = `${10*dpr}px sans-serif`;
      const raw = safeLabels[i];
      const t0 = (typeof raw === "string") ? raw : String(raw||"");
      const t = t0.length >= 10 ? t0.slice(5) : t0; // MM-DD when YYYY-MM-DD
      ctx.fillText(t, x, padT+plotH + 14*dpr);
      ctx.globalAlpha = 1;
    }
  }
}

function drawLine(canvas, labels, v1, v2){
  if(!canvas) return;
  const safeLabels = Array.isArray(labels) ? labels : [];
  const ctx = canvas.getContext("2d");
  const dpr = (window.devicePixelRatio||1);

  const w = canvas.width = Math.max(10, (canvas.clientWidth||600)) * dpr;
  const hh = canvas.getAttribute("height") ? Number(canvas.getAttribute("height")) : 120;
  const h = canvas.height = Math.max(40, hh) * dpr;
  ctx.clearRect(0,0,w,h);

  if(safeLabels.length === 0){
    ctx.globalAlpha = 0.75;
    ctx.fillStyle = "#9fb0c7";
    ctx.font = `${12*dpr}px sans-serif`;
    ctx.fillText("No severity trend data", 12*dpr, 20*dpr);
    ctx.globalAlpha = 1;
    return;
  }

  const padL = 28*dpr, padR = 8*dpr, padT = 10*dpr, padB = 22*dpr;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  const xs = safeLabels.map((_,i)=> padL + (safeLabels.length<=1?0:(i/(safeLabels.length-1))*plotW));

  const all = [];
  for(const v of (v1||[])) if(v!==null && v!==undefined) all.push(Number(v)||0);
  for(const v of (v2||[])) if(v!==null && v!==undefined) all.push(Number(v)||0);
  const maxV = Math.max(1, ...all);

  function yOf(v){
    const vv = Number(v)||0;
    return padT + plotH - (vv/maxV)*plotH;
  }

  ctx.globalAlpha = 0.5;
  ctx.fillStyle = "#9fb0c7";
  ctx.fillRect(padL, padT+plotH, plotW, 1*dpr);
  ctx.globalAlpha = 1;

  function drawOne(vals, alpha){
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = "#9fb0c7";
    ctx.lineWidth = 2*dpr;
    ctx.beginPath();
    let started=false;
    for(let i=0;i<(vals||[]).length;i++){
      const v = vals[i];
      if(v===null || v===undefined) continue;
      const x = xs[i] ?? xs[xs.length-1];
      const y = yOf(v);
      if(!started){ ctx.moveTo(x,y); started=true; }
      else ctx.lineTo(x,y);
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  drawOne(v1||[], 0.55);
  drawOne(v2||[], 0.25);

  for(let i=0;i<safeLabels.length;i++){
    if(i===0 || i===safeLabels.length-1 || safeLabels.length<=14 || (i%Math.ceil(safeLabels.length/6)===0)){
      ctx.globalAlpha = 0.7;
      ctx.fillStyle = "#9fb0c7";
      ctx.font = `${10*dpr}px sans-serif`;
      const raw = safeLabels[i];
      const t0 = (typeof raw === "string") ? raw : String(raw||"");
      const t = t0.length >= 10 ? t0.slice(5) : t0;
      ctx.fillText(t, xs[i], padT+plotH + 14*dpr);
      ctx.globalAlpha = 1;
    }
  }
}

async function loadRunsKpi(
""").lstrip("\n")

s2, n = pat.subn(replacement, s, count=1)
if n != 1:
    raise SystemExit("[ERR] cannot patch drawStackedBars/drawLine block safely (pattern mismatch).")

p.write_text(s2, encoding="utf-8")
print("[OK] patched KPI canvas guards")
PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_fix_runs_kpi_canvas_guard_v1"
