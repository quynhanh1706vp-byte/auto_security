#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_c_dashboard_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p116_${TS}"
echo "[OK] backup: ${F}.bak_p116_${TS}"

cat > "$F" <<'JS'
/* VSP_P116_C_DASHBOARD_WIRE_CHARTS_V1
 * No external libs. Renders mini trend SVG + TopCWE bars + KPIs.
 */
(() => {
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  function qparam(name){
    try { return new URLSearchParams(location.search).get(name); } catch(e){ return null; }
  }

  function detectRid(){
    const ridFromUrl = qparam("rid");
    if (ridFromUrl) return ridFromUrl;
    // Some templates put RID as an element id (you have id="VSP_CI_....")
    const el = $$('[id^="VSP_"]').find(x => x.id && x.id.includes("_"));
    if (el && el.id) return el.id;
    // fallback: persisted
    try { return localStorage.getItem("vsp_rid") || ""; } catch(e){ return ""; }
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = (v === null || v === undefined) ? "" : String(v);
  }

  async function fetchJson(url){
    const r = await fetch(url, { credentials: "same-origin" });
    const txt = await r.text();
    let j = null;
    try { j = JSON.parse(txt); } catch(e) {}
    return { ok: r.ok, status: r.status, json: j, text: txt };
  }

  function fmtTs(ts){
    try{
      const d = new Date(ts);
      if (!isNaN(d.getTime())) return d.toLocaleString();
    } catch(e){}
    return String(ts || "");
  }

  // ---------- Trend SVG ----------
  function renderTrendMini(points){
    const host = $("#trend-mini");
    if (!host) return;

    // normalize points into [{xLabel, y}]
    let series = [];
    if (Array.isArray(points)) {
      for (const p of points) {
        if (p == null) continue;
        // try common shapes
        let y =
          (typeof p.total === "number" ? p.total :
          typeof p.count === "number" ? p.count :
          typeof p.value === "number" ? p.value :
          typeof p.y === "number" ? p.y : null);
        let xLabel =
          (p.label ?? p.x ?? p.ts ?? p.time ?? "");
        if (y === null) continue;
        series.push({ xLabel, y });
      }
    }
    if (series.length < 2){
      host.innerHTML = `<div style="opacity:.75;font-size:12px">No trend data</div>`;
      return;
    }

    const W = 520, H = 90, P = 10;
    const ys = series.map(s => s.y);
    const minY = Math.min(...ys), maxY = Math.max(...ys);
    const span = (maxY - minY) || 1;

    const xAt = (i) => P + (i * (W - P*2) / (series.length - 1));
    const yAt = (y) => (H - P) - ((y - minY) * (H - P*2) / span);

    let d = "";
    for (let i=0;i<series.length;i++){
      const x = xAt(i), y = yAt(series[i].y);
      d += (i===0 ? `M ${x} ${y}` : ` L ${x} ${y}`);
    }

    const last = series[series.length-1];
    const first = series[0];

    host.innerHTML = `
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
        <div style="font-size:12px;opacity:.85">Trend (last=${last.y})</div>
        <div style="font-size:11px;opacity:.7">${String(first.xLabel).slice(0,16)} → ${String(last.xLabel).slice(0,16)}</div>
      </div>
      <svg viewBox="0 0 ${W} ${H}" width="100%" height="${H}" style="border:1px solid rgba(255,255,255,.06);border-radius:10px">
        <path d="${d}" fill="none" stroke="rgba(80,180,255,.95)" stroke-width="2"/>
        <circle cx="${xAt(series.length-1)}" cy="${yAt(last.y)}" r="3.5" fill="rgba(255,255,255,.95)"/>
      </svg>
    `;
  }

  // ---------- TopCWE bars ----------
  function renderTopCwe(items){
    const tb = $("#tb");
    if (!tb) return;

    let rows = [];
    if (Array.isArray(items)) {
      for (const it of items) {
        if (!it) continue;
        const name = it.cwe || it.id || it.key || it.name || it.title || "CWE";
        const n = it.count ?? it.total ?? it.n ?? it.value ?? 0;
        if (typeof n !== "number") continue;
        rows.push({ name: String(name), n });
      }
    }

    if (!rows.length){
      tb.innerHTML = `<div style="opacity:.75;font-size:12px">No TopCWE data</div>`;
      return;
    }

    rows = rows.sort((a,b)=>b.n-a.n).slice(0,8);
    const max = Math.max(...rows.map(r=>r.n)) || 1;

    tb.innerHTML = rows.map(r => {
      const w = Math.max(2, Math.round((r.n/max)*100));
      return `
        <div style="display:grid;grid-template-columns: 140px 1fr 50px;gap:10px;align-items:center;margin:6px 0">
          <div style="font-size:12px;opacity:.85;white-space:nowrap;overflow:hidden;text-overflow:ellipsis" title="${r.name}">${r.name}</div>
          <div style="height:10px;background:rgba(255,255,255,.06);border-radius:999px;overflow:hidden">
            <div style="height:10px;width:${w}%;background:rgba(255,120,120,.95);border-radius:999px"></div>
          </div>
          <div style="text-align:right;font-size:12px;opacity:.85">${r.n}</div>
        </div>
      `;
    }).join("");
  }

  // ---------- Main ----------
  async function main(){
    const rid = detectRid();
    if (rid) { try { localStorage.setItem("vsp_rid", rid); } catch(e){} }

    setText("k-status", "Loading…");
    setText("p-rid", rid || "(no rid)");
    setText("k-time", new Date().toLocaleString());

    // Buttons (optional)
    const br = $("#b-refresh");
    if (br && !br.dataset.p116){
      br.dataset.p116 = "1";
      br.addEventListener("click", () => {
        const u = new URL(location.href);
        u.searchParams.set("nocache","1");
        location.href = u.toString();
      });
    }

    // Fetch in parallel
    const base = "";
    const urls = {
      kpis: `${base}/api/vsp/dashboard_kpis_v4${rid ? `?rid=${encodeURIComponent(rid)}` : ""}`,
      trend: `${base}/api/vsp/trend_v1${rid ? `?rid=${encodeURIComponent(rid)}` : ""}`,
      topcwe: `${base}/api/vsp/topcwe_v1${rid ? `?rid=${encodeURIComponent(rid)}` : ""}`,
      top: `${base}/api/vsp/top_findings_v2?limit=5${rid ? `&rid=${encodeURIComponent(rid)}` : ""}`,
    };

    const [kpis, trend, topcwe, top] = await Promise.all([
      fetchJson(urls.kpis),
      fetchJson(urls.trend),
      fetchJson(urls.topcwe),
      fetchJson(urls.top),
    ]);

    // KPIs (best-effort parse)
    if (kpis.ok && kpis.json){
      const j = kpis.json;
      const total = j.total ?? j.kpi_total ?? j.count_total ?? j.summary?.total;
      setText("k-total", total ?? "");
      setText("k-from", j.from ?? j.label ?? j.ts ?? "");
    } else {
      // fallback: if top_findings returns something useful
      if (top.ok && top.json){
        setText("k-toplen", top.json.total ?? top.json.items?.length ?? "");
      }
    }

    // Trend
    if (trend.ok && trend.json){
      const pts = trend.json.points ?? trend.json.items ?? trend.json.data ?? trend.json;
      renderTrendMini(Array.isArray(pts) ? pts : []);
      setText("k-trend", Array.isArray(pts) ? pts.length : "");
      setText("k-trendmeta", trend.status);
    } else {
      renderTrendMini([]);
      setText("k-trendmeta", `trend ${trend.status}`);
    }

    // TopCWE
    if (topcwe.ok && topcwe.json){
      const items = topcwe.json.items ?? topcwe.json.data ?? topcwe.json;
      renderTopCwe(Array.isArray(items) ? items : []);
      setText("k-topmeta", topcwe.status);
    } else {
      renderTopCwe([]);
      setText("k-topmeta", `topcwe ${topcwe.status}`);
    }

    // Status
    const okAll = kpis.ok && trend.ok && topcwe.ok && top.ok;
    setText("k-status", okAll ? "OK" : "DEGRADED");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();
JS

echo "[OK] wrote $F"
echo "[OK] refresh browser: http://127.0.0.1:8910/c/dashboard?rid=<RID>"
