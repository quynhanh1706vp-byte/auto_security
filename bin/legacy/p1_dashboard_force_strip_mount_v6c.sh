#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_strip_v6c_${TS}"
echo "[BACKUP] ${JS}.bak_dash_strip_v6c_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_DASH_STRIP_FORCE_V6C"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* VSP_P1_DASH_STRIP_FORCE_V6C
   - robust mount: attach near Gate Story, re-attach if DOM replaced
   - live: poll /api/vsp/runs?limit=1 then fetch /api/vsp/run_file_allow rid + run_gate.json (fallback handled)
*/
(()=> {
  if (window.__vsp_p1_dash_strip_force_v6c) return;
  window.__vsp_p1_dash_strip_force_v6c = true;

  function isDash(){
    try{
      const p = (location && location.pathname) ? location.pathname : "";
      return (p === "/vsp5" || p === "/dashboard" || /\/vsp5\/?$/.test(p) || /\/dashboard\/?$/.test(p));
    }catch(e){ return false; }
  }
  if (!isDash()) return;

  const S = { live:true, rid:"", gate:null, running:false, base:8000, delay:8000, max:60000, backoff:0, t:null };

  const now = ()=>Date.now();
  const qs = (o)=>Object.keys(o).map(k=>encodeURIComponent(k)+"="+encodeURIComponent(o[k])).join("&");

  function findGateStoryAnchor(){
    // Try find element that contains "Gate Story"
    const nodes = Array.from(document.querySelectorAll("div,section,header,main"));
    for (const n of nodes){
      const txt = (n.textContent||"").trim();
      if (!txt) continue;
      if (txt.includes("Gate Story")){
        // choose a stable container: go up a bit
        let cur = n;
        for (let i=0;i<4 && cur && cur.parentElement; i++){
          if ((cur.className||"").toString().includes("container")) break;
          cur = cur.parentElement;
        }
        return cur || n;
      }
    }
    // fallback
    return document.querySelector("main") || document.body;
  }

  function ensureStrip(){
    let strip = document.getElementById("vsp_dash_strip_v6c");
    if (strip) return strip;

    const anchor = findGateStoryAnchor();
    strip = document.createElement("div");
    strip.id = "vsp_dash_strip_v6c";
    strip.style.cssText = [
      "margin:12px 0 14px 0",
      "padding:10px 12px",
      "border-radius:16px",
      "border:1px solid rgba(255,255,255,0.10)",
      "background:rgba(255,255,255,0.03)",
      "box-shadow:0 10px 30px rgba(0,0,0,0.20)"
    ].join(";");

    strip.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap">
        <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
          <span style="font-weight:800;opacity:.92">KPI</span>
          <span id="vsp_dash_strip_overall_v6c" style="padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.06);font-size:12px">OVERALL: --</span>
          <span id="vsp_dash_strip_rid_v6c" style="font-size:12px;opacity:.82">RID: --</span>
          <span id="vsp_dash_strip_last_v6c" style="font-size:12px;opacity:.72">Last: --</span>
        </div>
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
          <button id="vsp_dash_strip_live_v6c" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Live: ON</button>
          <button id="vsp_dash_strip_refresh_v6c" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Refresh</button>
          <button id="vsp_dash_strip_open_v6c" style="padding:6px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Open gate JSON</button>
        </div>
      </div>

      <div style="margin-top:10px;display:grid;grid-template-columns:repeat(6,minmax(110px,1fr));gap:10px">
        ${["TOTAL","HIGH","MEDIUM","LOW","INFO","CRITICAL"].map(k=>`
          <div style="padding:10px 10px;border-radius:14px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,255,255,0.02)">
            <div style="font-size:11px;opacity:.68">${k}</div>
            <div id="vsp_dash_strip_${k}_v6c" style="font-size:18px;font-weight:900;margin-top:2px">--</div>
          </div>
        `).join("")}
      </div>
    `;

    // insert: right BEFORE anchor if possible, else top of body
    try{
      if (anchor && anchor.parentElement){
        anchor.insertAdjacentElement("beforebegin", strip);
      } else {
        (document.body || document.documentElement).insertAdjacentElement("afterbegin", strip);
      }
    } catch(e){
      (document.body || document.documentElement).insertAdjacentElement("afterbegin", strip);
    }

    // events
    document.getElementById("vsp_dash_strip_live_v6c")?.addEventListener("click", ()=>{
      S.live = !S.live;
      document.getElementById("vsp_dash_strip_live_v6c").textContent = S.live ? "Live: ON" : "Live: OFF";
      if (S.live) kick("toggle_on");
    });
    document.getElementById("vsp_dash_strip_refresh_v6c")?.addEventListener("click", ()=>kick("manual"));
    document.getElementById("vsp_dash_strip_open_v6c")?.addEventListener("click", ()=>{
      if (!S.rid) return;
      window.open(`/api/vsp/run_file_allow?${qs({rid:S.rid, path:"run_gate.json"})}`, "_blank");
    });

    return strip;
  }

  function setTxt(id, t){ const e=document.getElementById(id); if(e) e.textContent=t; }

  function styleOverall(ov){
    const s = (ov||"UNKNOWN").toString().toUpperCase();
    const b = document.getElementById("vsp_dash_strip_overall_v6c");
    if (!b) return;
    let bg="rgba(255,255,255,0.06)", bd="rgba(255,255,255,0.10)";
    if (s==="GREEN"||s==="OK"||s==="PASS"){ bg="rgba(46,204,113,0.12)"; bd="rgba(46,204,113,0.25)"; }
    else if (s==="AMBER"||s==="WARN"){ bg="rgba(241,196,15,0.12)"; bd="rgba(241,196,15,0.25)"; }
    else if (s==="RED"||s==="FAIL"||s==="BLOCK"){ bg="rgba(231,76,60,0.12)"; bd="rgba(231,76,60,0.25)"; }
    else if (s==="DEGRADED"){ bg="rgba(155,89,182,0.12)"; bd="rgba(155,89,182,0.25)"; }
    b.textContent = `OVERALL: ${s}`;
    b.style.background = bg;
    b.style.borderColor = bd;
  }

  async function fetchLatestRid(){
    const r = await fetch(`/api/vsp/runs?limit=1&offset=0&_=${now()}`, {cache:"no-store", credentials:"same-origin"});
    if (!r.ok) throw new Error("runs "+r.status);
    const j = await r.json();
    const it = (j && j.items && j.items[0]) ? j.items[0] : null;
    return it ? String(it.rid || it.run_id || "") : "";
  }

  async function fetchGate(rid){
    const r = await fetch(`/api/vsp/run_file_allow?${qs({rid, path:"run_gate.json", _:now()})}`, {cache:"no-store", credentials:"same-origin"});
    if (!r.ok) return null;
    try{ return await r.json(); }catch(e){ return null; }
  }

  function render(g){
    ensureStrip();
    const ct = (g && (g.counts_total||g.counts||g.totals)) ? (g.counts_total||g.counts||g.totals) : {};
    const total = (ct.HIGH||0)+(ct.MEDIUM||0)+(ct.LOW||0)+(ct.INFO||0)+(ct.CRITICAL||0)+(ct.TRACE||0);
    setTxt("vsp_dash_strip_TOTAL_v6c", String(total));
    setTxt("vsp_dash_strip_HIGH_v6c", String(ct.HIGH??"--"));
    setTxt("vsp_dash_strip_MEDIUM_v6c", String(ct.MEDIUM??"--"));
    setTxt("vsp_dash_strip_LOW_v6c", String(ct.LOW??"--"));
    setTxt("vsp_dash_strip_INFO_v6c", String(ct.INFO??"--"));
    setTxt("vsp_dash_strip_CRITICAL_v6c", String(ct.CRITICAL??"--"));
    styleOverall(g && (g.overall||g.overall_status));
  }

  function schedule(ms){ clearTimeout(S.t); S.t=setTimeout(()=>tick("timer"), ms); }
  function kick(){ schedule(200); }

  async function tick(reason){
    ensureStrip(); // also re-attach if missing
    if (!S.live && reason!=="manual") return schedule(S.base);
    if (document.hidden) return schedule(S.base);
    if (S.running) return schedule(600);

    S.running = true;
    try{
      const rid = await fetchLatestRid();
      const changed = rid && rid !== S.rid;
      if (rid) S.rid = rid;
      setTxt("vsp_dash_strip_rid_v6c", `RID: ${S.rid||"--"}`);

      if (changed || !S.gate || reason==="manual"){
        S.gate = await fetchGate(S.rid);
      }
      if (S.gate) render(S.gate);

      setTxt("vsp_dash_strip_last_v6c", `Last: ${new Date().toLocaleTimeString()}${changed ? " • new" : ""}`);
      S.backoff=0; S.delay=S.base;
      schedule(S.delay);
    } catch(e){
      S.backoff += 1;
      S.delay = Math.min(S.max, Math.max(S.base, S.base * (2 ** Math.min(5, S.backoff))));
      setTxt("vsp_dash_strip_last_v6c", `Last: ${new Date().toLocaleTimeString()} • err • backoff ${Math.round(S.delay/1000)}s`);
      schedule(S.delay);
    } finally {
      S.running = false;
    }
  }

  // Re-attach if GateStory re-renders
  const mo = new MutationObserver(()=>{ if (!document.getElementById("vsp_dash_strip_v6c")) ensureStrip(); });
  try{ mo.observe(document.documentElement, {subtree:true, childList:true}); }catch(e){}

  document.addEventListener("visibilitychange", ()=>{ if (!document.hidden && S.live) kick(); });

  // Boot after DOM ready
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ ensureStrip(); schedule(800); });
  } else {
    ensureStrip(); schedule(800);
  }
})();
""").rstrip()+"\n"

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended", marker)
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2
echo "[DONE] V6C mounted. Open /vsp5, hard refresh (Ctrl+Shift+R)."
