#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

# auto-detect dashboard js
F=""
for cand in \
  "static/js/vsp_dashboard_enhance_v1.js" \
  "static/js/dashboard_render.js" \
  "static/js/vsp_dashboard_kpi_v1.js"
do
  if [ -f "$cand" ]; then F="$cand"; break; fi
done
[ -n "${F:-}" ] || { echo "[ERR] cannot find dashboard js to patch"; exit 2; }

echo "== PATCH DASHBOARD TREND SPARKLINE =="
echo "[FILE] $F"
cp -f "$F" "$F.bak_trend_${TS}" && echo "[BACKUP] $F.bak_trend_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("${F}")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="/* VSP_DASH_TREND_SPARKLINE_V1_BEGIN */"
END  ="/* VSP_DASH_TREND_SPARKLINE_V1_END */"
s=re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n?", "", s, flags=re.S)

block = r'''
/* VSP_DASH_TREND_SPARKLINE_V1_BEGIN */
(function(){
  'use strict';

  if (window.__VSP_DASH_TREND_SPARKLINE_V1_INSTALLED) return;
  window.__VSP_DASH_TREND_SPARKLINE_V1_INSTALLED = true;

  const LOGP = "[VSP_TREND]";
  const API = "/api/vsp/runs_index_v3_fs_resolved?limit=20&hide_empty=0&filter=1";

  function q(sel){ try{return document.querySelector(sel);}catch(e){return null;} }
  function mountPoint(){
    return (
      q("#vsp4-dashboard") ||
      q("#tab-dashboard") ||
      q("[data-tab='dashboard']") ||
      q("#dashboard") ||
      q(".vsp-dashboard") ||
      q("main") ||
      document.body
    );
  }

  function el(tag, attrs, children){
    const n=document.createElement(tag);
    if (attrs){
      for (const k of Object.keys(attrs)){
        if (k === "class") n.className = attrs[k];
        else if (k === "style") n.setAttribute("style", attrs[k]);
        else n.setAttribute(k, attrs[k]);
      }
    }
    if (children){
      for (const c of children){
        if (c == null) continue;
        if (typeof c === "string") n.appendChild(document.createTextNode(c));
        else n.appendChild(c);
      }
    }
    return n;
  }

  function drawSpark(canvas, series){
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0,0,w,h);

    if (!Array.isArray(series) || series.length < 2){
      ctx.globalAlpha = 0.6;
      ctx.fillText("no data", 6, 14);
      ctx.globalAlpha = 1;
      return;
    }

    // normalize
    let min=Infinity, max=-Infinity;
    for (const v of series){
      if (typeof v !== "number" || !isFinite(v)) continue;
      min = Math.min(min, v);
      max = Math.max(max, v);
    }
    if (!isFinite(min) || !isFinite(max)){ min=0; max=1; }
    if (max === min) max = min + 1;

    const pad = 6;
    const xStep = (w - pad*2) / (series.length - 1);

    function y(v){
      const t = (v - min) / (max - min);
      return (h - pad) - t * (h - pad*2);
    }

    // grid line (mid)
    ctx.globalAlpha = 0.18;
    ctx.beginPath();
    ctx.moveTo(pad, Math.round(h/2)+0.5);
    ctx.lineTo(w-pad, Math.round(h/2)+0.5);
    ctx.stroke();
    ctx.globalAlpha = 1;

    // line
    ctx.beginPath();
    for (let i=0;i<series.length;i++){
      const v = (typeof series[i] === "number" && isFinite(series[i])) ? series[i] : 0;
      const xx = pad + i*xStep;
      const yy = y(v);
      if (i===0) ctx.moveTo(xx,yy);
      else ctx.lineTo(xx,yy);
    }
    ctx.lineWidth = 2;
    ctx.stroke();

    // last dot
    const lastV = (typeof series[series.length-1] === "number" && isFinite(series[series.length-1])) ? series[series.length-1] : 0;
    ctx.beginPath();
    ctx.arc(w-pad, y(lastV), 2.6, 0, Math.PI*2);
    ctx.fill();
  }

  function fmtInt(n){
    try { return (Number(n)||0).toLocaleString(); } catch(e){ return String(n||0); }
  }

  async function run(){
    try{
      const res = await fetch(API, {cache:"no-store"});
      if (!res.ok) { console.warn(LOGP, "runs_index not ok", res.status); return; }
      const js = await res.json();
      const items = (js && js.items) ? js.items : [];
      if (!Array.isArray(items) || items.length === 0) return;

      // API returns newest-first; render oldest->newest
      const rows = items.slice().reverse();

      const findings = rows.map(it => Number(it.total_findings ?? it.findings_total ?? it.total ?? 0) || 0);
      const degraded = rows.map(it => {
        const any = (it.degraded_any ?? it.is_degraded);
        const dn = Number(it.degraded_n ?? it.degraded_count ?? 0) || 0;
        return (any === true || dn > 0) ? 1 : 0;
      });

      const latest = rows[rows.length-1] || {};
      const latestRid = latest.run_id || latest.id || "";

      // build card
      const root = mountPoint();
      if (!root) return;

      // avoid duplicate mount
      if (q("#vsp-trend-sparkline-card")) return;

      const card = el("div", {
        id: "vsp-trend-sparkline-card",
        class: "vsp-card vsp-card-trend",
        style: [
          "margin-top:14px",
          "border:1px solid rgba(148,163,184,.16)",
          "background:rgba(2,6,23,.72)",
          "border-radius:14px",
          "padding:14px 14px 12px",
          "box-shadow:0 10px 30px rgba(0,0,0,.25)"
        ].join(";")
      }, []);

      const header = el("div", {style:"display:flex;justify-content:space-between;gap:12px;align-items:baseline;flex-wrap:wrap;"}, [
        el("div", null, [
          el("div", {style:"font-weight:700;font-size:14px;letter-spacing:.2px;"}, ["Trend (last 20 runs)"]),
          el("div", {style:"opacity:.75;font-size:12px;margin-top:4px;"}, [
            "Latest: ", latestRid ? latestRid : "(unknown)",
            " • Findings: ", fmtInt(findings[findings.length-1]),
            " • Degraded: ", degraded[degraded.length-1] ? "YES" : "NO"
          ])
        ]),
        el("div", {style:"opacity:.75;font-size:12px;"}, [
          el("span", {style:"display:inline-flex;align-items:center;gap:6px;margin-right:12px;"}, [
            el("span", {style:"width:10px;height:2px;display:inline-block;background:currentColor;opacity:.95;"}, []),
            "Findings"
          ]),
          el("span", {style:"display:inline-flex;align-items:center;gap:6px;"}, [
            el("span", {style:"width:10px;height:2px;display:inline-block;background:currentColor;opacity:.6;"}, []),
            "Degraded"
          ])
        ])
      ]);

      const grid = el("div", {style:"display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px;"}, []);

      function panel(title, canvasId){
        const c = el("canvas", {id:canvasId, width:"520", height:"88",
          style:"width:100%;height:88px;border-radius:12px;border:1px solid rgba(148,163,184,.12);background:rgba(15,23,42,.55);"
        }, []);
        const box = el("div", {style:"padding:10px 10px 8px;border-radius:12px;background:rgba(15,23,42,.35);border:1px solid rgba(148,163,184,.10);"}, [
          el("div", {style:"font-size:12px;opacity:.8;margin-bottom:8px;font-weight:600;"}, [title]),
          c
        ]);
        return {box, canvas:c};
      }

      const p1 = panel("Total Findings", "vsp-trend-findings");
      const p2 = panel("Degraded (0/1)", "vsp-trend-degraded");
      grid.appendChild(p1.box);
      grid.appendChild(p2.box);

      card.appendChild(header);
      card.appendChild(grid);

      // append after KPI section if possible; else end of dashboard
      const anchor = q("#vsp-kpi-wrap") || q("#vsp-kpi-cards") || q(".vsp-kpi") || null;
      if (anchor && anchor.parentElement){
        anchor.parentElement.insertBefore(card, anchor.nextSibling);
      } else {
        root.appendChild(card);
      }

      // set drawing color via current text color (no explicit colors)
      try{
        const css = window.getComputedStyle(card);
        p1.canvas.getContext("2d").strokeStyle = css.color || "#e5e7eb";
        p1.canvas.getContext("2d").fillStyle = css.color || "#e5e7eb";
        p2.canvas.getContext("2d").strokeStyle = css.color || "#e5e7eb";
        p2.canvas.getContext("2d").fillStyle = css.color || "#e5e7eb";
      } catch(e){}

      drawSpark(p1.canvas, findings);
      drawSpark(p2.canvas, degraded);

      // tooltips
      p1.canvas.title = "Total Findings per run (old→new): " + findings.join(", ");
      p2.canvas.title = "Degraded per run (old→new): " + degraded.join(", ");

      console.log(LOGP, "trend rendered", {points: rows.length});
    }catch(e){
      console.warn(LOGP, "trend error", e);
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
  else run();
})();
 /* VSP_DASH_TREND_SPARKLINE_V1_END */
'''.strip("\n") + "\n"

s = s.rstrip() + "\n\n" + block
p.write_text(s, encoding="utf-8")
print("[OK] appended trend sparkline v1")
PY

node --check "$F" >/dev/null && echo "[OK] dashboard JS syntax OK"
echo "[DONE] Trend sparkline injected into $F. Hard refresh Ctrl+Shift+R."
