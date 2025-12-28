#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_real_kpi_${TS}"
echo "[BACKUP] ${JS}.bak_dash_real_kpi_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_DASH_REAL_KPI_LIVE_V6"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* VSP_P1_DASH_REAL_KPI_LIVE_V6
   - poll /api/vsp/runs?limit=1 (light)
   - fetch gate via /api/vsp/run_file_allow?rid=RID&path=run_gate.json (fallback summary handled by backend)
   - render KPI strip + by-tool mini table
   - pause when hidden + backoff on errors
*/
(()=> {
  if (window.__vsp_p1_dash_real_kpi_live_v6) return;
  window.__vsp_p1_dash_real_kpi_live_v6 = true;

  function isDash(){
    try{
      const p = (location && location.pathname) ? location.pathname : "";
      return (p === "/vsp5" || p === "/dashboard" || /\/vsp5\/?$/.test(p) || /\/dashboard\/?$/.test(p));
    }catch(e){ return false; }
  }
  if (!isDash()) return;

  const S = {
    live: true,
    baseDelay: 8000,
    delay: 8000,
    maxDelay: 60000,
    backoffN: 0,
    rid: "",
    gate: null,
    running: false,
    timer: null
  };

  const now = ()=> Date.now();
  const qs = (o)=>Object.keys(o).map(k=>encodeURIComponent(k)+"="+encodeURIComponent(o[k])).join("&");

  function el(id){ return document.getElementById(id); }
  function setTxt(id, t){ const e=el(id); if (e) e.textContent = t; }

  function badge(ov){
    const s = (ov||"UNKNOWN").toString().toUpperCase();
    let bg="rgba(255,255,255,0.06)", bd="rgba(255,255,255,0.10)", fg="rgba(255,255,255,0.92)";
    if (s==="GREEN" || s==="OK" || s==="PASS"){ bg="rgba(46, 204, 113, 0.12)"; bd="rgba(46, 204, 113, 0.25)"; }
    else if (s==="AMBER" || s==="WARN"){ bg="rgba(241, 196, 15, 0.12)"; bd="rgba(241, 196, 15, 0.25)"; }
    else if (s==="RED" || s==="FAIL" || s==="BLOCK"){ bg="rgba(231, 76, 60, 0.12)"; bd="rgba(231, 76, 60, 0.25)"; }
    else if (s==="DEGRADED"){ bg="rgba(155, 89, 182, 0.12)"; bd="rgba(155, 89, 182, 0.25)"; }
    return {s, bg, bd, fg};
  }

  function ensureUI(){
    if (el("vsp_dash_kpi_strip_v6")) return;

    const host =
      document.querySelector("#vsp_tab_dashboard") ||
      document.querySelector("[data-tab='dashboard']") ||
      document.querySelector("main") ||
      document.body;

    const wrap = document.createElement("div");
    wrap.id = "vsp_dash_kpi_strip_v6";
    wrap.style.cssText = [
      "margin:12px 0 14px 0",
      "padding:12px 12px",
      "border-radius:16px",
      "border:1px solid rgba(255,255,255,0.10)",
      "background:rgba(255,255,255,0.03)",
      "box-shadow:0 10px 30px rgba(0,0,0,0.20)"
    ].join(";");

    wrap.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">
        <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
          <span style="font-weight:700;opacity:.92">Dashboard</span>
          <span id="vsp_dash_overall_badge_v6" style="padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.06);font-size:12px;opacity:.95">OVERALL: --</span>
          <span id="vsp_dash_rid_v6" style="font-size:12px;opacity:.82">RID: --</span>
          <span id="vsp_dash_ts_v6" style="font-size:12px;opacity:.72">TS: --</span>
          <span id="vsp_dash_last_v6" style="font-size:12px;opacity:.72">Last: --</span>
        </div>
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
          <button id="vsp_dash_live_toggle_v6" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Live: ON</button>
          <button id="vsp_dash_refresh_v6" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Refresh</button>
          <button id="vsp_dash_open_gate_v6" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Open gate JSON</button>
          <button id="vsp_dash_open_html_v6" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Open HTML</button>
        </div>
      </div>

      <div style="margin-top:10px;display:grid;grid-template-columns:repeat(6,minmax(120px,1fr));gap:10px">
        ${["TOTAL","HIGH","MEDIUM","LOW","INFO","CRITICAL"].map(k=>`
          <div style="padding:10px 10px;border-radius:14px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,255,255,0.02)">
            <div style="font-size:11px;opacity:.68">${k}</div>
            <div id="vsp_dash_cnt_${k}_v6" style="font-size:20px;font-weight:800;letter-spacing:.2px;margin-top:2px">--</div>
          </div>
        `).join("")}
      </div>

      <div style="margin-top:12px;display:flex;gap:12px;flex-wrap:wrap">
        <div style="flex:1;min-width:300px;padding:10px 10px;border-radius:14px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,255,255,0.02)">
          <div style="font-size:12px;font-weight:700;opacity:.85;margin-bottom:6px">By tool</div>
          <div id="vsp_dash_bytool_v6" style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;font-size:12px;opacity:.92">--</div>
        </div>
        <div style="flex:1;min-width:300px;padding:10px 10px;border-radius:14px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,255,255,0.02)">
          <div style="font-size:12px;font-weight:700;opacity:.85;margin-bottom:6px">Notes</div>
          <div id="vsp_dash_notes_v6" style="font-size:12px;opacity:.85;line-height:1.4">
            • Click-only: no bulk probing<br/>
            • Source: run_gate.json (fallback summary)<br/>
            • Severity normalized: CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE
          </div>
        </div>
      </div>
    `;

    host.insertAdjacentElement("afterbegin", wrap);

    el("vsp_dash_live_toggle_v6").addEventListener("click", ()=>{
      S.live = !S.live;
      el("vsp_dash_live_toggle_v6").textContent = S.live ? "Live: ON" : "Live: OFF";
      if (S.live) kick("toggle_on");
    });
    el("vsp_dash_refresh_v6").addEventListener("click", ()=> kick("manual"));

    el("vsp_dash_open_gate_v6").addEventListener("click", ()=>{
      if (!S.rid) return;
      window.open(`/api/vsp/run_file_allow?${qs({rid:S.rid, path:"run_gate.json"})}`, "_blank");
    });
    el("vsp_dash_open_html_v6").addEventListener("click", ()=>{
      if (!S.rid) return;
      window.open(`/api/vsp/run_file_allow?${qs({rid:S.rid, path:"reports/findings_unified.html"})}`, "_blank");
    });
  }

  async function fetchLatestRid(){
    const url = `/api/vsp/runs?limit=1&offset=0&_=${now()}`;
    const r = await fetch(url, { cache:"no-store", credentials:"same-origin" });
    if (!r.ok) throw new Error("runs "+r.status);
    const j = await r.json();
    const it = (j && j.items && j.items[0]) ? j.items[0] : null;
    if (!it) return "";
    return (it.rid || it.run_id || it.id || "").toString();
  }

  async function fetchGate(rid){
    const url = `/api/vsp/run_file_allow?${qs({rid, path:"run_gate.json", _: now()})}`;
    const r = await fetch(url, { cache:"no-store", credentials:"same-origin" });
    if (!r.ok) return null;
    try { return await r.json(); } catch(e){ return null; }
  }

  function render(g){
    ensureUI();

    const rid = S.rid || "--";
    const ts = (g && (g.ts || g.time || g.generated_at)) ? (g.ts || g.time || g.generated_at) : "--";
    const ov = (g && (g.overall || g.overall_status)) ? (g.overall || g.overall_status) : "UNKNOWN";

    const b = badge(ov);
    const ob = el("vsp_dash_overall_badge_v6");
    if (ob){
      ob.textContent = `OVERALL: ${b.s}`;
      ob.style.background = b.bg;
      ob.style.borderColor = b.bd;
      ob.style.color = b.fg;
    }

    setTxt("vsp_dash_rid_v6", `RID: ${rid}`);
    setTxt("vsp_dash_ts_v6", `TS: ${ts}`);

    const ct = (g && (g.counts_total || g.counts || g.totals)) ? (g.counts_total || g.counts || g.totals) : {};
    const total = (ct.HIGH||0)+(ct.MEDIUM||0)+(ct.LOW||0)+(ct.INFO||0)+(ct.CRITICAL||0)+(ct.TRACE||0);

    setTxt("vsp_dash_cnt_TOTAL_v6", total.toString());
    setTxt("vsp_dash_cnt_HIGH_v6", (ct.HIGH??"--").toString());
    setTxt("vsp_dash_cnt_MEDIUM_v6", (ct.MEDIUM??"--").toString());
    setTxt("vsp_dash_cnt_LOW_v6", (ct.LOW??"--").toString());
    setTxt("vsp_dash_cnt_INFO_v6", (ct.INFO??"--").toString());
    setTxt("vsp_dash_cnt_CRITICAL_v6", (ct.CRITICAL??"--").toString());

    // By-tool mini table (top 10 by HIGH+MEDIUM)
    const bt = (g && g.by_tool) ? g.by_tool : {};
    const rows = Object.keys(bt).map(k=>{
      const x = bt[k] || {};
      const c = x.counts_total || x.counts || {};
      const hi = c.HIGH||0, me=c.MEDIUM||0, lo=c.LOW||0, inf=c.INFO||0, cr=c.CRITICAL||0;
      return {k, hi, me, lo, inf, cr, score: (hi*1000 + me*100 + lo*10 + inf)};
    }).sort((a,b)=>b.score-a.score).slice(0,10);

    const lines = rows.length ? rows.map(r=>{
      const k = (r.k||"").padEnd(10, " ").slice(0,10);
      return `${k}  C:${r.cr}  H:${r.hi}  M:${r.me}  L:${r.lo}  I:${r.inf}`;
    }).join("\n") : "--";

    const btEl = el("vsp_dash_bytool_v6");
    if (btEl){
      btEl.textContent = lines;
      btEl.style.whiteSpace = "pre";
    }
  }

  function schedule(ms){
    clearTimeout(S.timer);
    S.timer = setTimeout(()=>tick("timer"), ms);
  }
  function kick(reason){ schedule(250); }

  async function tick(reason){
    if (!S.live && reason !== "manual") return schedule(S.baseDelay);
    if (document.hidden) return schedule(S.baseDelay);
    if (S.running) return schedule(600);

    S.running = true;
    try{
      ensureUI();

      const rid = await fetchLatestRid();
      const changed = rid && rid !== S.rid;
      if (rid) S.rid = rid;

      let g = S.gate;
      if (changed || !g || reason === "manual"){
        g = await fetchGate(S.rid);
        S.gate = g;
      }

      const last = new Date().toLocaleTimeString();
      setTxt("vsp_dash_last_v6", `Last: ${last}${changed ? " • new RID" : ""}`);

      if (g) render(g);

      S.backoffN = 0;
      S.delay = S.baseDelay;
      schedule(S.delay);
    } catch(e){
      S.backoffN += 1;
      S.delay = Math.min(S.maxDelay, Math.max(S.baseDelay, S.baseDelay * (2 ** Math.min(5, S.backoffN))));
      const last = new Date().toLocaleTimeString();
      setTxt("vsp_dash_last_v6", `Last: ${last} • err • backoff ${Math.round(S.delay/1000)}s`);
      schedule(S.delay);
    } finally {
      S.running = false;
    }
  }

  document.addEventListener("visibilitychange", ()=>{ if (!document.hidden && S.live) kick("visible"); });

  // boot
  ensureUI();
  schedule(800);
})();
""").rstrip() + "\n"

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended", marker)
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2
echo "[DONE] Restarted. Open /vsp5 and you should see KPI strip on top."
