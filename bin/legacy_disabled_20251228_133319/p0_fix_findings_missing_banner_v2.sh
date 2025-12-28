#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need grep

JS="static/js/vsp_dashboard_consistency_patch_v1.js"
mkdir -p static/js

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_findings_banner_${TS}" 2>/dev/null || true
echo "[BACKUP] ${JS}.bak_findings_banner_${TS}"

cat > "$JS" <<'JS'
/* VSP_P0_FINDINGS_MISSING_BANNER_V1
 * Show banner when: findings_unified is missing/empty BUT counts_total > 0 for the run.
 * Button: Open Data Source -> /data_source?rid=...
 */
(function(){
  "use strict";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function getRID(){
    try{
      const u = new URL(window.location.href);
      return (u.searchParams.get("rid")||"").trim();
    }catch(e){ return ""; }
  }

  function sumCounts(obj){
    if(!obj || typeof obj !== "object") return 0;
    let s = 0;
    for(const k of Object.keys(obj)){
      const v = obj[k];
      if(typeof v === "number" && isFinite(v)) s += v;
      else if(v && typeof v === "object"){
        // tolerate nested
        for(const kk of Object.keys(v)){
          const vv = v[kk];
          if(typeof vv === "number" && isFinite(vv)) s += vv;
        }
      }
    }
    return s;
  }

  async function fetchJSON(url, timeoutMs){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs||4000);
    try{
      const r = await fetch(url, {credentials:"same-origin", signal: ctrl.signal});
      const txt = await r.text();
      try{ return JSON.parse(txt); } catch(_){ return null; }
    }catch(_e){
      return null;
    }finally{
      clearTimeout(t);
    }
  }

  async function tryGateSummary(rid){
    const base = "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=";
    const candidates = ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"];
    for(const p of candidates){
      const j = await fetchJSON(base + encodeURIComponent(p), 3500);
      if(j && typeof j === "object"){
        // gate file itself often has ok/counts_total
        if(j.counts_total || j.by_tool || j.ok !== undefined) return j;
      }
    }
    return null;
  }

  async function tryFindings(rid){
    const url = "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid)
              + "&path=" + encodeURIComponent("findings_unified.json")
              + "&limit=1";
    const j = await fetchJSON(url, 4500);
    return j;
  }

  function findInjectAnchor(){
    // Prefer a stable container if present
    const anchors = [
      "#vsp-dashboard-main",
      "#vsp-dashboard-root",
      "main",
      ".container",
      ".dashboard",
      "body"
    ];
    for(const a of anchors){
      const el = qs(a);
      if(el) return el;
    }
    return document.body;
  }

  function findTopFindingsCard(){
    // Best-effort: locate a card whose heading contains "Top Findings"
    const cards = qsa(".card, .vsp-card, .panel, section, article, div");
    for(const c of cards){
      const h = c.querySelector("h1,h2,h3,h4,.title,.card-title");
      const t = (h ? (h.textContent||"") : (c.getAttribute("data-title")||"")).toLowerCase();
      if(t.includes("top findings") || t.includes("findings") && t.includes("top")) return c;
    }
    return null;
  }

  function ensureBanner(rid){
    const existing = qs("#vsp-findings-missing-banner");
    if(existing) return existing;

    const el = document.createElement("div");
    el.id = "vsp-findings-missing-banner";
    el.setAttribute("role","alert");
    el.style.cssText = [
      "border:1px solid rgba(255,193,7,0.35)",
      "background:rgba(255,193,7,0.10)",
      "color:#ffd36a",
      "padding:12px 14px",
      "border-radius:12px",
      "margin:12px 0",
      "display:flex",
      "align-items:center",
      "justify-content:space-between",
      "gap:12px",
      "font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial",
      "font-size:14px"
    ].join(";");

    const left = document.createElement("div");
    left.textContent = "⚠ Findings file missing for this run (rid=" + rid + "). counts_total > 0 nhưng findings_unified rỗng/missing.";

    const right = document.createElement("div");
    right.style.cssText = "display:flex; gap:10px; align-items:center;";

    const btn = document.createElement("a");
    btn.textContent = "Open Data Source";
    btn.href = "/data_source?rid=" + encodeURIComponent(rid);
    btn.style.cssText = [
      "display:inline-block",
      "padding:8px 10px",
      "border-radius:10px",
      "border:1px solid rgba(255,193,7,0.45)",
      "background:rgba(255,193,7,0.14)",
      "color:#ffe08a",
      "text-decoration:none",
      "font-weight:600"
    ].join(";");

    const close = document.createElement("button");
    close.type = "button";
    close.textContent = "×";
    close.title = "Dismiss";
    close.style.cssText = [
      "width:34px",
      "height:34px",
      "border-radius:10px",
      "border:1px solid rgba(255,255,255,0.12)",
      "background:rgba(255,255,255,0.06)",
      "color:#e6e6e6",
      "cursor:pointer",
      "font-size:18px",
      "line-height:1"
    ].join(";");

    close.addEventListener("click", ()=>{ try{ el.remove(); }catch(_e){} });

    right.appendChild(btn);
    right.appendChild(close);

    el.appendChild(left);
    el.appendChild(right);
    return el;
  }

  async function main(){
    const rid = getRID();
    if(!rid) return;

    const gate = await tryGateSummary(rid);
    const countsTotal = gate && gate.counts_total ? gate.counts_total : null;
    const countsSum = sumCounts(countsTotal);

    // only care when counts_total > 0
    if(!(countsSum > 0)) return;

    const f = await tryFindings(rid);
    const findingsArr = (f && Array.isArray(f.findings)) ? f.findings : null;
    const findingsLen = findingsArr ? findingsArr.length : 0;

    // If request failed or findings empty => show banner
    const shouldBanner = (!f) || (findingsArr && findingsLen === 0) || (!findingsArr && (f.ok === false));

    if(!shouldBanner) return;

    const banner = ensureBanner(rid);

    // Prefer insert inside Top Findings card if found, else prepend to main anchor
    const topCard = findTopFindingsCard();
    if(topCard){
      topCard.insertBefore(banner, topCard.firstChild);
      return;
    }
    const anchor = findInjectAnchor();
    anchor.insertBefore(banner, anchor.firstChild);
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", main);
  }else{
    main();
  }
})();
JS

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P0_FINDINGS_MISSING_BANNER_V1" "$JS" | head -n 3 && echo "[OK] marker present"
