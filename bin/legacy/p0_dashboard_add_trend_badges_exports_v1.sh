#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

BUNDLE="static/js/vsp_bundle_commercial_v2.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_dash_enh_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_dash_enh_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASH_ENHANCER_TREND_BADGES_EXPORTS_V1"
if marker in s:
    print("[OK] enhancer already present")
    raise SystemExit(0)

addon = r"""
/* VSP_P0_DASH_ENHANCER_TREND_BADGES_EXPORTS_V1 */
(()=> {
  if (window.__vsp_p0_dash_enh_v1) return;
  window.__vsp_p0_dash_enh_v1 = true;

  const isDash = ()=> {
    try{ return (location.pathname||"") === "/vsp5"; }catch(e){ return false; }
  };

  const TOOL_ORDER = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];

  function el(tag, attrs, html){
    const x = document.createElement(tag);
    if (attrs){
      for (const k of Object.keys(attrs)){
        if (k==="class") x.className = attrs[k];
        else if (k==="style") x.setAttribute("style", attrs[k]);
        else x.setAttribute(k, attrs[k]);
      }
    }
    if (html != null) x.innerHTML = html;
    return x;
  }

  function css(){
    return `
#vspDashEnh{
  margin-top: 12px;
  display: grid;
  grid-template-columns: 1.2fr 1fr;
  gap: 12px;
}
@media (max-width: 1100px){
  #vspDashEnh{ grid-template-columns: 1fr; }
}
.vspCard{
  border-radius: 14px;
  border: 1px solid rgba(255,255,255,0.08);
  background: rgba(255,255,255,0.03);
  padding: 12px;
}
.vspCard h3{
  margin: 0 0 8px 0;
  font-size: 13px;
  opacity: 0.9;
  letter-spacing: 0.2px;
}
.vspRow{display:flex; gap:10px; flex-wrap:wrap; align-items:center;}
.vspPill{
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(0,0,0,0.18);
  font-size: 12px;
  cursor: default;
}
.vspPill.ok{border-color: rgba(144,238,144,0.35);}
.vspPill.warn{border-color: rgba(255,210,125,0.35);}
.vspPill.bad{border-color: rgba(255,120,120,0.35);}
.vspMini{
  font-size: 12px; opacity: 0.8;
}
#vspTrendSvg{ width: 100%; height: 56px; display:block; }
.vspBtn{
  padding: 8px 10px;
  border-radius: 10px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.04);
  color: #e9eefc;
  cursor: pointer;
  font-size: 12px;
}
.vspBtn:hover{ background: rgba(255,255,255,0.07); }
code{opacity:0.9;}
`;
  }

  async function fetchJSON(url){
    const r = await fetch(url, {credentials:"same-origin"});
    if (!r.ok) throw new Error("HTTP "+r.status);
    return await r.json();
  }

  function pickRid(){
    try{
      const r = String(window.__VSP_SELECTED_RID||"").trim();
      if (r) return r;
    }catch(e){}
    try{
      const ls = (localStorage.getItem("vsp_selected_rid")||"").trim();
      if (ls) return ls;
    }catch(e){}
    return "";
  }

  function ensureMount(){
    if (document.getElementById("vspDashEnh")) return;
    const st = el("style", null, css());
    document.head.appendChild(st);

    // try place under existing "Commercial Panels" area; else after RID bar; else top of body
    const after = document.querySelector("#vspRidBar") || document.querySelector(".vsp5-shell") || document.body;
    const mount = el("div", {id:"vspDashEnh"});
    mount.appendChild(el("div", {class:"vspCard", id:"vspDashTrendCard"}, `
      <h3>Run Trend (last 30)</h3>
      <div class="vspRow" id="vspTrendStats"></div>
      <svg id="vspTrendSvg" viewBox="0 0 600 56" preserveAspectRatio="none"></svg>
      <div class="vspMini" id="vspTrendHint">Auto updates on RID change.</div>
    `));
    mount.appendChild(el("div", {class:"vspCard", id:"vspDashActionsCard"}, `
      <h3>Quick Actions</h3>
      <div class="vspRow" id="vspToolBadges"></div>
      <div style="height:10px"></div>
      <div class="vspRow" id="vspExportBtns"></div>
      <div class="vspMini" id="vspActionHint"></div>
    `));

    // insert after RID bar if possible
    if (after && after.insertAdjacentElement){
      after.insertAdjacentElement("afterend", mount);
    }else{
      document.body.prepend(mount);
    }
  }

  function drawSpark(svg, ys){
    while (svg.firstChild) svg.removeChild(svg.firstChild);
    const W=600, H=56;
    if (!ys || ys.length < 2) return;
    const max = Math.max(...ys.map(x=> Number(x)||0), 1);
    const min = Math.min(...ys.map(x=> Number(x)||0), 0);
    const span = Math.max(1, max - min);
    const n = ys.length;

    const pts = ys.map((v,i)=>{
      const x = (i/(n-1))*W;
      const y = H - ((Number(v)-min)/span)*H;
      return [x,y];
    });

    const path = document.createElementNS("http://www.w3.org/2000/svg","path");
    const d = pts.map((p,i)=> (i===0?`M ${p[0].toFixed(2)} ${p[1].toFixed(2)}`:`L ${p[0].toFixed(2)} ${p[1].toFixed(2)}`)).join(" ");
    path.setAttribute("d", d);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke-width", "2");
    path.setAttribute("stroke", "currentColor");
    path.setAttribute("opacity", "0.9");
    svg.appendChild(path);
  }

  function pill(text, cls){
    const x = el("span", {class:"vspPill "+(cls||"")}, text);
    return x;
  }

  async function loadTrend(){
    const stats = document.getElementById("vspTrendStats");
    const svg = document.getElementById("vspTrendSvg");
    if (!stats || !svg) return;

    stats.innerHTML = "";
    stats.appendChild(pill("loading…"));

    try{
      const j = await fetchJSON("/api/vsp/runs?limit=30");
      const runs = (j && j.runs) ? j.runs : (Array.isArray(j)? j : []);
      // For each run, try to infer overall/total from fields if present; fallback just count.
      const totals = [];
      let red=0, amber=0, green=0;

      for (const r of runs){
        const overall = String(r.overall || r.status || "").toUpperCase();
        if (overall==="RED") red++;
        else if (overall==="AMBER" || overall==="YELLOW") amber++;
        else if (overall==="GREEN") green++;

        const t = (r.total_findings ?? r.total ?? r.count_total ?? r.counts_total ?? null);
        if (typeof t === "number") totals.push(t);
        else totals.push(0);
      }

      stats.innerHTML = "";
      stats.appendChild(pill("runs: "+runs.length, "ok"));
      stats.appendChild(pill("GREEN: "+green, "ok"));
      stats.appendChild(pill("AMBER: "+amber, "warn"));
      stats.appendChild(pill("RED: "+red, "bad"));

      drawSpark(svg, totals.reverse());
    }catch(e){
      stats.innerHTML = "";
      stats.appendChild(pill("trend unavailable", "warn"));
    }
  }

  async function loadBadgesAndExports(){
    const rid = pickRid();
    const badges = document.getElementById("vspToolBadges");
    const btns = document.getElementById("vspExportBtns");
    const hint = document.getElementById("vspActionHint");
    if (!badges || !btns || !hint) return;

    badges.innerHTML = "";
    btns.innerHTML = "";
    hint.textContent = "";

    if (!rid){
      badges.appendChild(pill("RID not set", "warn"));
      return;
    }

    // Tool badges (from run_gate_summary.json if exists)
    try{
      const sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
      const by_tool = sum && sum.by_tool ? sum.by_tool : null;

      for (const name of TOOL_ORDER){
        let cls = "ok";
        let txt = name;
        try{
          const t = by_tool ? (by_tool[name] || by_tool[name.toLowerCase()] || null) : null;
          const degraded = !!(t && (t.degraded || t.timeout || t.missing));
          if (degraded) cls = "warn";
          if (t && t.missing) cls = "bad";
          if (t && t.timeout) cls = "warn";
          if (t && t.status) txt = `${name}: ${String(t.status).toUpperCase()}`;
        }catch(e){}
        badges.appendChild(pill(txt, cls));
      }
    }catch(e){
      // fallback: show only RID
      badges.appendChild(pill("RID: "+rid, "ok"));
      badges.appendChild(pill("tool summary unavailable", "warn"));
    }

    // Export buttons (best-effort; open in new tab)
    const mk = (label, path)=> {
      const b = el("button", {class:"vspBtn", type:"button"}, label);
      b.addEventListener("click", ()=> {
        const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
        window.open(url, "_blank", "noopener");
      });
      return b;
    };

    btns.appendChild(mk("Download CSV", "reports/findings_unified.csv"));
    btns.appendChild(mk("Download SARIF", "reports/findings_unified.sarif"));
    btns.appendChild(mk("Download JSON", "findings_unified.json"));
    btns.appendChild(mk("Gate Summary", "run_gate_summary.json"));

    // Optional: HTML report
    const bHtml = el("button", {class:"vspBtn", type:"button"}, "Open HTML Report");
    bHtml.addEventListener("click", ()=> {
      const candidates = [
        "reports/findings_unified.html",
        "reports/report.html",
        "reports/checkmarx_like.html",
      ];
      // open first candidate (server may 404; acceptable)
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(candidates[0])}`;
      window.open(url, "_blank", "noopener");
    });
    btns.appendChild(bHtml);

    hint.textContent = `RID=${rid} • Exports are allowlisted; if a file is missing you'll see 404.`;
  }

  function boot(){
    if (!isDash()) return;
    ensureMount();
    loadTrend();
    loadBadgesAndExports();
    // refresh on rid change
    window.addEventListener("vsp:rid", ()=> {
      loadBadgesAndExports();
    });
    // refresh trend every 60s (light)
    setInterval(()=> { if (isDash()) loadTrend(); }, 60000);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended dashboard enhancer (trend+badges+exports) to bundle")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$BUNDLE" && echo "[OK] node --check bundle OK"
fi

echo "[DONE] Hard refresh: Ctrl+Shift+R  http://127.0.0.1:8910/vsp5"
