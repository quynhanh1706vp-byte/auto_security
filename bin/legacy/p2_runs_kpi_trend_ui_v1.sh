#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TPL="templates/vsp_runs_reports_v1.html"
JS="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_p2_runs_kpi_${TS}"
cp -f "$JS"  "${JS}.bak_p2_runs_kpi_${TS}"
echo "[BACKUP] ${TPL}.bak_p2_runs_kpi_${TS}"
echo "[BACKUP] ${JS}.bak_p2_runs_kpi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_RUNS_KPI_PANEL_V1" not in s:
    panel = textwrap.dedent(r"""
    <!-- ===================== VSP_P2_RUNS_KPI_PANEL_V1 ===================== -->
    <section class="vsp-card" id="vsp_runs_kpi_panel" style="margin:14px 0 10px 0;">
      <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <div style="display:flex;flex-direction:column;gap:2px;">
          <div style="font-weight:700;font-size:16px;letter-spacing:.2px;">Runs — Operational KPI</div>
          <div style="opacity:.75;font-size:12px;">Server-side KPI (safe allowlist). Unknown should trend to 0.</div>
        </div>
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
          <label style="font-size:12px;opacity:.8;">Window</label>
          <select id="vsp_runs_kpi_days" class="vsp-input" style="min-width:110px;">
            <option value="7">7 days</option>
            <option value="14">14 days</option>
            <option value="30" selected>30 days</option>
            <option value="60">60 days</option>
          </select>
          <button id="vsp_runs_kpi_reload" class="vsp-btn" type="button">Reload KPI</button>
        </div>
      </div>

      <div id="vsp_runs_kpi_cards" style="display:grid;grid-template-columns:repeat(6,minmax(140px,1fr));gap:10px;margin-top:10px;">
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Runs (window / all)</div>
          <div style="font-size:18px;font-weight:800;"><span id="kpi_runs_window">—</span> <span style="opacity:.6;font-size:12px;">/</span> <span id="kpi_runs_all" style="opacity:.85;">—</span></div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Pass / Warn / Fail</div>
          <div style="font-size:18px;font-weight:800;">
            <span id="kpi_green">—</span> <span style="opacity:.5;">/</span>
            <span id="kpi_amber">—</span> <span style="opacity:.5;">/</span>
            <span id="kpi_red">—</span>
          </div>
          <div style="opacity:.7;font-size:12px;">Unknown: <span id="kpi_unknown">—</span></div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Degraded rate</div>
          <div style="font-size:18px;font-weight:800;"><span id="kpi_degraded_rate">—</span></div>
          <div style="opacity:.7;font-size:12px;">Count: <span id="kpi_degraded_count">—</span></div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Avg / P95 duration</div>
          <div style="font-size:18px;font-weight:800;"><span id="kpi_avg_dur">—</span> <span style="opacity:.55;font-size:12px;">/</span> <span id="kpi_p95_dur" style="opacity:.9;">—</span></div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Top bottleneck</div>
          <div style="font-size:18px;font-weight:800;" id="kpi_bottleneck">—</div>
          <div style="opacity:.7;font-size:12px;" id="kpi_bottleneck_hint">—</div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="opacity:.75;font-size:12px;">Degraded reasons (top)</div>
          <div style="font-size:12px;opacity:.9;max-height:46px;overflow:auto;" id="kpi_degraded_reasons">—</div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1.2fr .8fr;gap:10px;margin-top:10px;">
        <div class="vsp-card" style="padding:10px;">
          <div style="font-weight:700;font-size:13px;margin-bottom:6px;">Overall status trend (stacked)</div>
          <canvas id="vsp_runs_trend_canvas" height="120" style="width:100%;"></canvas>
          <div style="opacity:.7;font-size:12px;margin-top:6px;">Best-effort: status per day from run_gate_summary.json.</div>
        </div>
        <div class="vsp-card" style="padding:10px;">
          <div style="font-weight:700;font-size:13px;margin-bottom:6px;">CRITICAL/HIGH trend (if available)</div>
          <canvas id="vsp_runs_sev_canvas" height="120" style="width:100%;"></canvas>
          <div style="opacity:.7;font-size:12px;margin-top:6px;">If gate summary includes severity counts; otherwise blank.</div>
        </div>
      </div>
    </section>
    <!-- ===================== /VSP_P2_RUNS_KPI_PANEL_V1 ===================== -->
    """).strip("\n")

    # Insert near top of main content; safe heuristic: after first <main ...> or after nav header
    if "<main" in s:
        s = re.sub(r"(?is)(<main[^>]*>)", r"\1\n"+panel+"\n", s, count=1)
    else:
        # fallback: before first big table container
        s = panel + "\n" + s

    tpl.write_text(s, encoding="utf-8")
    print("[OK] inserted KPI panel into template")
else:
    print("[OK] template already has KPI panel")

js = Path("static/js/vsp_runs_reports_overlay_v1.js")
j = js.read_text(encoding="utf-8", errors="replace")
if "VSP_P2_RUNS_KPI_JS_V1" not in j:
    addon = textwrap.dedent(r"""
    /* ===================== VSP_P2_RUNS_KPI_JS_V1 ===================== */
    (function(){
      function $id(x){ return document.getElementById(x); }
      function fmtSec(v){
        if(v===null || v===undefined || isNaN(v)) return "—";
        const s = Math.round(Number(v));
        if(s < 60) return s+"s";
        const m = Math.floor(s/60), r = s%60;
        if(m < 60) return m+"m "+r+"s";
        const h = Math.floor(m/60), mm = m%60;
        return h+"h "+mm+"m";
      }
      function fmtPct(v){
        if(v===null || v===undefined || isNaN(v)) return "—";
        return Math.round(Number(v)*1000)/10 + "%";
      }

      function drawStackedBars(canvas, labels, series){
        // series: [{name, values:[], color?}, ...]  (no color forcing; use grayscale-ish by alpha)
        if(!canvas) return;
        const ctx = canvas.getContext("2d");
        const w = canvas.width = canvas.clientWidth * (window.devicePixelRatio||1);
        const h = canvas.height = (canvas.getAttribute("height")? Number(canvas.getAttribute("height")):120) * (window.devicePixelRatio||1);
        ctx.clearRect(0,0,w,h);

        const padL = 28*(window.devicePixelRatio||1);
        const padR = 8*(window.devicePixelRatio||1);
        const padT = 10*(window.devicePixelRatio||1);
        const padB = 22*(window.devicePixelRatio||1);

        const plotW = w - padL - padR;
        const plotH = h - padT - padB;
        const n = labels.length || 1;
        const barW = Math.max(2*(window.devicePixelRatio||1), Math.floor(plotW / n) - 2*(window.devicePixelRatio||1));

        // totals
        const totals = labels.map((_,i)=> series.reduce((a,s)=> a + (Number(s.values[i]||0)), 0));
        const maxT = Math.max(1, ...totals);

        // axes baseline
        ctx.globalAlpha = 0.5;
        ctx.fillStyle = "#9fb0c7";
        ctx.fillRect(padL, padT+plotH, plotW, 1*(window.devicePixelRatio||1));
        ctx.globalAlpha = 1;

        for(let i=0;i<n;i++){
          const x = padL + i*(barW+2*(window.devicePixelRatio||1));
          let y = padT + plotH;
          const tot = totals[i] || 1;

          // draw stack: UNKNOWN->RED->AMBER->GREEN order for intuitive visual
          const ordered = series.slice();
          for(const s of ordered){
            const v = Number(s.values[i]||0);
            if(v<=0) continue;
            const bh = Math.max(1, Math.round((v/maxT)*plotH));
            y -= bh;

            // no hard colors: use opacity layers
            ctx.globalAlpha = s.alpha || 0.25;
            ctx.fillStyle = "#9fb0c7";
            ctx.fillRect(x, y, barW, bh);
          }
          ctx.globalAlpha = 1;

          // x label (every few)
          if(i===0 || i===n-1 || (n<=14) || (i%Math.ceil(n/6)===0)){
            ctx.globalAlpha = 0.7;
            ctx.fillStyle = "#9fb0c7";
            ctx.font = `${10*(window.devicePixelRatio||1)}px sans-serif`;
            const t = labels[i].slice(5); // MM-DD
            ctx.fillText(t, x, padT+plotH + 14*(window.devicePixelRatio||1));
            ctx.globalAlpha = 1;
          }
        }
      }

      function drawLine(canvas, labels, v1, v2){
        if(!canvas) return;
        const ctx = canvas.getContext("2d");
        const w = canvas.width = canvas.clientWidth * (window.devicePixelRatio||1);
        const h = canvas.height = (canvas.getAttribute("height")? Number(canvas.getAttribute("height")):120) * (window.devicePixelRatio||1);
        ctx.clearRect(0,0,w,h);

        const padL = 28*(window.devicePixelRatio||1);
        const padR = 8*(window.devicePixelRatio||1);
        const padT = 10*(window.devicePixelRatio||1);
        const padB = 22*(window.devicePixelRatio||1);

        const plotW = w - padL - padR;
        const plotH = h - padT - padB;

        const xs = labels.map((_,i)=> padL + (labels.length<=1?0:(i/(labels.length-1))*plotW));
        const all = []
        for(const v of v1) if(v!==null && v!==undefined) all.push(Number(v)||0);
        for(const v of v2) if(v!==null && v!==undefined) all.push(Number(v)||0);
        const maxV = Math.max(1, ...all);

        function yOf(v){
          const vv = Number(v)||0;
          return padT + plotH - (vv/maxV)*plotH;
        }

        // axis
        ctx.globalAlpha = 0.5;
        ctx.fillStyle = "#9fb0c7";
        ctx.fillRect(padL, padT+plotH, plotW, 1*(window.devicePixelRatio||1));
        ctx.globalAlpha = 1;

        function drawOne(vals, alpha){
          ctx.globalAlpha = alpha;
          ctx.strokeStyle = "#9fb0c7";
          ctx.lineWidth = 2*(window.devicePixelRatio||1);
          ctx.beginPath();
          let started=false;
          for(let i=0;i<vals.length;i++){
            const v = vals[i];
            if(v===null || v===undefined) continue;
            const x = xs[i], y = yOf(v);
            if(!started){ ctx.moveTo(x,y); started=true; }
            else ctx.lineTo(x,y);
          }
          ctx.stroke();
          ctx.globalAlpha = 1;
        }

        drawOne(v1, 0.55);
        drawOne(v2, 0.25);

        // x labels sparse
        for(let i=0;i<labels.length;i++){
          if(i===0 || i===labels.length-1 || (labels.length<=14) || (i%Math.ceil(labels.length/6)===0)){
            ctx.globalAlpha = 0.7;
            ctx.fillStyle = "#9fb0c7";
            ctx.font = `${10*(window.devicePixelRatio||1)}px sans-serif`;
            const t = labels[i].slice(5);
            ctx.fillText(t, xs[i], padT+plotH + 14*(window.devicePixelRatio||1));
            ctx.globalAlpha = 1;
          }
        }
      }

      async function loadRunsKpi(){
        const daysSel = $id("vsp_runs_kpi_days");
        const days = daysSel ? (daysSel.value||"30") : "30";
        const url = `/api/ui/runs_kpi_v1?days=${encodeURIComponent(days)}`;
        try{
          const r = await fetch(url, {cache:"no-store"});
          const j = await r.json();
          if(!j || !j.ok) throw new Error((j&&j.err)||"kpi failed");

          $id("kpi_runs_window").textContent = j.total_days ?? "—";
          $id("kpi_runs_all").textContent = j.total_all ?? "—";

          const st = j.status_days || {};
          $id("kpi_green").textContent = st.GREEN ?? 0;
          $id("kpi_amber").textContent = st.AMBER ?? 0;
          $id("kpi_red").textContent = st.RED ?? 0;
          $id("kpi_unknown").textContent = st.UNKNOWN ?? 0;

          $id("kpi_degraded_count").textContent = j.degraded_days ?? 0;
          $id("kpi_degraded_rate").textContent = fmtPct(j.degraded_rate_days);

          $id("kpi_avg_dur").textContent = fmtSec(j.avg_duration_sec_days);
          $id("kpi_p95_dur").textContent = fmtSec(j.p95_duration_sec_days);

          const bn = j.bottleneck_tool || {};
          $id("kpi_bottleneck").textContent = bn.tool || "—";
          $id("kpi_bottleneck_hint").textContent = bn.hint || "—";

          const dr = j.degraded_reasons_top || [];
          $id("kpi_degraded_reasons").innerHTML = dr.length
            ? dr.map(x=>`<div style="display:flex;justify-content:space-between;gap:10px;"><span style="opacity:.9;">${(x.reason||"").replace(/</g,"&lt;")}</span><span style="opacity:.7;">${x.count||0}</span></div>`).join("")
            : "—";

          // Trend
          const tr = j.trend_days || [];
          const labels = tr.map(x=>x.day);
          const vUnknown = tr.map(x=>x.UNKNOWN||0);
          const vRed = tr.map(x=>x.RED||0);
          const vAmber = tr.map(x=>x.AMBER||0);
          const vGreen = tr.map(x=>x.GREEN||0);

          // draw stacked (use alpha as "layers")
          drawStackedBars(
            $id("vsp_runs_trend_canvas"),
            labels,
            [
              {name:"UNKNOWN", values:vUnknown, alpha:0.14},
              {name:"RED", values:vRed, alpha:0.40},
              {name:"AMBER", values:vAmber, alpha:0.28},
              {name:"GREEN", values:vGreen, alpha:0.18},
            ]
          );

          // Severity trend (best effort)
          const vC = tr.map(x=> (x.CRITICAL===null||x.CRITICAL===undefined) ? null : Number(x.CRITICAL));
          const vH = tr.map(x=> (x.HIGH===null||x.HIGH===undefined) ? null : Number(x.HIGH));
          drawLine($id("vsp_runs_sev_canvas"), labels, vC, vH);

        }catch(e){
          console.warn("[RUNS_KPI] failed:", e);
          const p = $id("vsp_runs_kpi_panel");
          if(p){
            const msg = document.createElement("div");
            msg.style.marginTop = "10px";
            msg.style.opacity = "0.8";
            msg.style.fontSize = "12px";
            msg.textContent = "KPI load failed (safe API). Check server patch / restart.";
            p.appendChild(msg);
          }
        }
      }

      function hookRunsKpi(){
        const btn = $id("vsp_runs_kpi_reload");
        if(btn && !btn.__vsp_hooked){
          btn.__vsp_hooked = true;
          btn.addEventListener("click", loadRunsKpi);
        }
        const sel = $id("vsp_runs_kpi_days");
        if(sel && !sel.__vsp_hooked){
          sel.__vsp_hooked = true;
          sel.addEventListener("change", loadRunsKpi);
        }
        // first load after small delay (let page render)
        setTimeout(loadRunsKpi, 120);
        window.addEventListener("resize", ()=> setTimeout(loadRunsKpi, 120));
      }

      // Try hook when DOM ready
      if(document.readyState === "loading"){
        document.addEventListener("DOMContentLoaded", hookRunsKpi);
      } else {
        hookRunsKpi();
      }
    })();
    /* ===================== /VSP_P2_RUNS_KPI_JS_V1 ===================== */
    """).strip("\n")

    j = j + "\n\n" + addon + "\n"
    js.write_text(j, encoding="utf-8")
    print("[OK] appended KPI JS")
else:
    print("[OK] JS already has KPI patch")

PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_trend_ui_v1"
