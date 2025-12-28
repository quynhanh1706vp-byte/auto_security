#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_live_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] && cp -f "$F" "${F}.bak_${TS}" && echo "[BACKUP] ${F}.bak_${TS}"

cat > "$F" <<'EOF'
"use strict";
/**
 * VSP_DASHBOARD_LIVE_V2 (commercial-fit)
 * - rid-aware + pin-aware
 * - top_findings_v3c (respect limit)
 * - escapeHtml for safety
 * - no heavy DOM (tables only)
 */
(function(){
  // LocalStorage pin key đang dùng ở badge/pin suite
  const LS_PIN_KEY = "vsp_pin_mode_v2"; // auto|global|rid

  function qs(name){
    try { return new URLSearchParams(location.search).get(name) || ""; }
    catch(e){ return ""; }
  }
  function getRid(){ return qs("rid"); }
  function getPin(){
    try{
      const v = (localStorage.getItem(LS_PIN_KEY) || "auto").toLowerCase();
      return (v==="auto"||v==="global"||v==="rid") ? v : "auto";
    }catch(e){ return "auto"; }
  }
  function withRidPin(url){
    const rid = getRid();
    const pin = getPin();
    try{
      const u = new URL(url, location.origin);
      if (rid) u.searchParams.set("rid", rid);
      if (pin) u.searchParams.set("pin", pin);
      return u.pathname + "?" + u.searchParams.toString();
    }catch(e){
      // url có thể là path dạng "/api/.."
      const sep = url.includes("?") ? "&" : "?";
      return url + (rid ? (sep+"rid="+encodeURIComponent(rid)) : "")
               + (pin ? ("&pin="+encodeURIComponent(pin)) : "");
    }
  }

  function $(id){ return document.getElementById(id); }

  function escapeHtml(s){
    s = (s==null) ? "" : String(s);
    return s.replace(/[&<>"']/g, (c)=>({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
    }[c]));
  }

  async function fetchJson(url, timeoutMs=8000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const res = await fetch(url, { cache:"no-store", signal: ctrl.signal });
      const text = await res.text();
      if (!res.ok) throw new Error("HTTP "+res.status+" for "+url+" body="+text.slice(0,120));
      try { return JSON.parse(text); }
      catch(e){ throw new Error("JSON parse fail for "+url+" head="+text.slice(0,120)); }
    } finally {
      clearTimeout(t);
    }
  }

  function safeInt(v){
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  const fmt = (n)=> safeInt(n).toLocaleString("en-US");

  function setNoDataRow(tbody, msg){
    if (!tbody) return;
    tbody.innerHTML = '<tr><td colspan="10" style="color:#9ca3c7;font-size:11px;">'+escapeHtml(msg)+'</td></tr>';
  }

  // ====== Render blocks (tùy DOM bạn có hay không) ======
  function renderHeaderMeta(meta){
    // meta: { total_findings, from_path, rid_used, data_source, pin_mode }
    const elTotal = $("kpi-total-findings");
    if (elTotal) elTotal.textContent = fmt(meta.total_findings);

    const elRid = $("vsp-last-run-id");
    if (elRid) elRid.textContent = meta.rid_used || getRid() || "–";

    const elTs = $("vsp-last-run-ts");
    if (elTs) elTs.textContent = meta.ts || meta.label || "";

    // optional small fields if you have ids
    const elFrom = $("vsp-from-path");
    if (elFrom) elFrom.textContent = meta.from_path || "";
    const elDS = $("vsp-data-source");
    if (elDS) elDS.textContent = meta.data_source || "";
    const elPin = $("vsp-pin-mode");
    if (elPin) elPin.textContent = meta.pin_mode || getPin();
  }

  function renderTopFindingsTable(resp){
    const tbody = document.querySelector("#top-findings-table tbody");
    if (!tbody) return;

    const items = Array.isArray(resp.items) ? resp.items : [];
    if (!items.length){
      setNoDataRow(tbody, "Không có dữ liệu top findings.");
      return;
    }
    const rows = items.map(it=>{
      const sev = escapeHtml((it.severity||it.level||"").toUpperCase());
      const title = escapeHtml(it.title || it.rule || it.rule_id || it.cwe || "(no title)");
      const tool = escapeHtml(it.tool || it.source || "");
      const file = escapeHtml(it.file || it.path || it.location || "");
      return `<tr>
        <td><span class="vsp-severity-pill">${sev}</span></td>
        <td>${title}</td>
        <td>${tool}</td>
        <td>${file}</td>
      </tr>`;
    });
    tbody.innerHTML = rows.join("");
  }

  function renderTrendMini(resp){
    // nếu bạn có chart canvas thì tự dùng Chart; nếu không, không sao
    const ctx = document.getElementById("trend_line_chart");
    if (!ctx || typeof Chart === "undefined") return;

    const points = Array.isArray(resp.points) ? resp.points : [];
    if (!points.length) return;

    const labels = points.map(p=>p.label||p.run_id||"");
    const totals = points.map(p=>safeInt(p.total));

    if (window.__vspTrendChart){ try{ window.__vspTrendChart.destroy(); }catch(e){} }
    window.__vspTrendChart = new Chart(ctx, {
      type:"line",
      data:{ labels, datasets:[{ label:"Total", data: totals, tension:0.35, borderWidth:2, pointRadius:2 }] },
      options:{ responsive:true, maintainAspectRatio:false, plugins:{ legend:{display:false} },
        scales:{ x:{ grid:{display:false} }, y:{ beginAtZero:true } }
      }
    });
  }

  // ====== Loaders (chỉ dùng các API bạn đang probe OK) ======
  async function loadMeta(){
    // dùng findings_page_v3 để lấy total_findings + from_path (đã chứng minh OK)
    const url = withRidPin("/api/vsp/findings_page_v3?limit=1&offset=0");
    const j = await fetchJson(url);
    if (j && j.ok===false) throw new Error("findings_page_v3 not ok");
    renderHeaderMeta({
      total_findings: j.total_findings,
      from_path: j.from_path,
      rid_used: j.rid_used || getRid(),
      data_source: j.data_source,
      pin_mode: j.pin_mode
    });
    return j;
  }

  async function loadTopFindings(){
    const url = withRidPin("/api/vsp/top_findings_v3c?limit=200");
    const j = await fetchJson(url);
    if (j && j.ok===false) throw new Error("top_findings_v3c not ok");
    renderTopFindingsTable(j);
    return j;
  }

  async function loadTrend(){
    const url = withRidPin("/api/vsp/trend_v1");
    const j = await fetchJson(url);
    if (j && j.ok===false) throw new Error("trend_v1 not ok");
    renderTrendMini(j);
    return j;
  }

  async function loadAll(){
    // song song để nhanh, nhưng vẫn freeze-safe
    await Promise.allSettled([ loadMeta(), loadTopFindings(), loadTrend() ]);
  }

  window.VSP_DASHBOARD_LIVE_V2_INIT = function(){
    loadAll().catch(err=>console.error("[VSP_DASHBOARD_LIVE_V2] loadAll err:", err));
  };
})();
EOF

echo "[OK] wrote $F"
echo "[NEXT] Include it in your /c/dashboard template and call VSP_DASHBOARD_LIVE_V2_INIT() on DOMContentLoaded."
