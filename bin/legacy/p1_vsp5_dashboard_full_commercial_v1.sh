#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_dash_full_${TS}"
echo "[BACKUP] ${JS}.bak_dash_full_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_DASH_FULL_COMMERCIAL_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_VSP5_DASH_FULL_COMMERCIAL_V1
   Enhance injected /vsp5 dashboard:
   - Add Run Snapshot card + Severity Donut + Top Findings table (from findings_unified.json)
   - Styling align with enterprise dark (5 tabs)
*/
(()=> {
  try{
    if (window.__vsp_p1_vsp5_dash_full_v1) return;
    window.__vsp_p1_vsp5_dash_full_v1 = true;

    const isDash = ()=> (location && location.pathname && location.pathname.indexOf("/vsp5") === 0);
    if (!isDash()) return;

    const $ = (id)=> document.getElementById(id);
    const esc = (s)=> (s==null? "" : String(s)).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
    const sleep = (ms)=> new Promise(r=>setTimeout(r, ms));

    async function fetchJSON(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) throw new Error("http "+r.status+" "+url);
      return await r.json();
    }
    async function fetchText(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) throw new Error("http "+r.status+" "+url);
      return await r.text();
    }

    function ensureStyle(){
      const id="vsp5_dash_full_style_v1";
      if ($(id)) return;
      const st=document.createElement("style");
      st.id=id;
      st.textContent=`
        /* Full dashboard add-ons */
        #vsp_dash_grid_full{ display:grid; grid-template-columns:repeat(12,1fr); gap:10px; margin-top:10px; }
        .vsp_card h3{ margin:0; font-size:12px; opacity:.78; font-weight:700; letter-spacing:.2px; }
        .vsp_kv{ display:grid; grid-template-columns: 120px 1fr; gap:6px 10px; margin-top:10px; font-size:12px; }
        .vsp_kv .k{ opacity:.72; }
        .vsp_kv .v{ opacity:.95; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size:11.5px; }
        .vsp_tbl{ width:100%; border-collapse:collapse; margin-top:10px; font-size:12px; }
        .vsp_tbl th,.vsp_tbl td{ border-bottom:1px solid rgba(255,255,255,.08); padding:8px 8px; vertical-align:top; }
        .vsp_tbl th{ text-align:left; opacity:.78; font-weight:700; }
        .sev_badge{ padding:4px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.04); font-size:11px; display:inline-block; }
        .sev_CRITICAL{ border-color: rgba(255,72,72,.30); background: rgba(255,72,72,.12); }
        .sev_HIGH{ border-color: rgba(255,120,72,.30); background: rgba(255,120,72,.10); }
        .sev_MEDIUM{ border-color: rgba(255,190,64,.30); background: rgba(255,190,64,.10); }
        .sev_LOW{ border-color: rgba(140,200,255,.26); background: rgba(140,200,255,.08); }
        .sev_INFO{ border-color: rgba(160,160,160,.22); background: rgba(160,160,160,.08); }
        .sev_TRACE{ border-color: rgba(120,120,120,.18); background: rgba(120,120,120,.06); }
        .donut_wrap{ display:flex; gap:14px; align-items:center; margin-top:10px; flex-wrap:wrap; }
        .donut{ width:88px; height:88px; border-radius:50%; background:conic-gradient(rgba(255,72,72,.0) 0 100%); border:1px solid rgba(255,255,255,.10); box-shadow:0 10px 28px rgba(0,0,0,.40); position:relative; }
        .donut:after{ content:""; position:absolute; inset:12px; border-radius:50%; background: rgba(0,0,0,.24); border:1px solid rgba(255,255,255,.08); }
        .donut_center{ position:absolute; inset:0; display:flex; align-items:center; justify-content:center; font-size:12px; opacity:.85; font-weight:800; }
        .legend{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
        .dot{ width:10px; height:10px; border-radius:3px; border:1px solid rgba(255,255,255,.12); display:inline-block; margin-right:6px; opacity:.9; }
        .lg{ font-size:12px; opacity:.86; display:flex; align-items:center; }
      `;
      (document.head||document.documentElement).appendChild(st);
    }

    function ensureContainers(){
      const wrap = $("vsp_dash_p1_wrap");
      if (!wrap) return false;

      // ensure a "full" grid under existing cards
      if ($("vsp_dash_grid_full")) return true;

      const full = document.createElement("div");
      full.id = "vsp_dash_grid_full";
      full.style.gridTemplateColumns = "repeat(12,1fr)";
      full.className = "";
      // append after the first injected grid (the KPI row)
      wrap.appendChild(full);

      // cards
      const c1 = document.createElement("div");
      c1.className = "vsp_card";
      c1.style.gridColumn = "span 4";
      c1.innerHTML = `
        <h3>Run Snapshot</h3>
        <div class="vsp_kv" id="vsp_run_kv">
          <div class="k">RID</div><div class="v" id="vsp_run_rid">—</div>
          <div class="k">Overall</div><div class="v" id="vsp_run_overall">—</div>
          <div class="k">Degraded</div><div class="v" id="vsp_run_degraded">—</div>
          <div class="k">Updated</div><div class="v" id="vsp_run_updated">—</div>
          <div class="k">Gate file</div><div class="v" id="vsp_run_gatefile">—</div>
        </div>
        <div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
          <a class="vsp_btn" id="vsp_run_open_runs" href="/runs" style="text-decoration:none;">Open Runs</a>
          <a class="vsp_btn" id="vsp_run_open_data" href="/data_source" style="text-decoration:none;">Open Data</a>
          <a class="vsp_btn" id="vsp_run_zip2" href="#" style="text-decoration:none;">Export ZIP</a>
          <a class="vsp_btn" id="vsp_run_pdf2" href="#" style="text-decoration:none;">Export PDF</a>
        </div>
      `;

      const c2 = document.createElement("div");
      c2.className = "vsp_card";
      c2.style.gridColumn = "span 4";
      c2.innerHTML = `
        <h3>Severity Overview</h3>
        <div class="donut_wrap">
          <div class="donut" id="vsp_sev_donut"><div class="donut_center" id="vsp_sev_total">—</div></div>
          <div class="legend" id="vsp_sev_legend"></div>
        </div>
        <div style="margin-top:10px;opacity:.72;font-size:12px;">
          Uses unified severity scale: CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE.
        </div>
      `;

      const c3 = document.createElement("div");
      c3.className = "vsp_card";
      c3.style.gridColumn = "span 12";
      c3.innerHTML = `
        <div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:center;">
          <h3 style="margin:0;">Top Findings (preview)</h3>
          <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
            <span class="vsp_pill" id="vsp_findings_meta">—</span>
            <a class="vsp_btn" href="/data_source" style="text-decoration:none;">View all in Data Source</a>
          </div>
        </div>
        <table class="vsp_tbl">
          <thead>
            <tr>
              <th style="width:110px;">Severity</th>
              <th style="width:110px;">Tool</th>
              <th>Title / Rule</th>
              <th style="width:30%;">File</th>
            </tr>
          </thead>
          <tbody id="vsp_findings_rows">
            <tr><td colspan="4" style="opacity:.7;">Loading…</td></tr>
          </tbody>
        </table>
      `;

      full.appendChild(c1);
      full.appendChild(c2);
      full.appendChild(c3);

      return true;
    }

    function normalizeCounts(sum){
      const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      const c = sum?.counts_by_severity || sum?.by_severity || sum?.severity_counts || sum?.summary?.counts_by_severity || null;
      if (c && typeof c === "object"){
        for (const k of Object.keys(out)) out[k] = Number(c[k] || 0) || 0;
      }
      return out;
    }

    function sevBadge(sev){
      const s = (sev||"").toUpperCase();
      const cls = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].includes(s) ? s : "INFO";
      return `<span class="sev_badge sev_${cls}">${esc(cls)}</span>`;
    }

    function renderDonut(counts){
      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const total = order.reduce((a,k)=>a+(counts[k]||0),0) || 0;
      const el = $("vsp_sev_donut");
      const center = $("vsp_sev_total");
      const legend = $("vsp_sev_legend");
      if (!el || !center || !legend) return;

      center.textContent = total ? String(total) : "0";

      // use alpha-only palette (no explicit colors) by varying opacity of white + severity-specific tints via CSS-ish
      // We'll build conic with mild tints
      const tint = {
        CRITICAL:"rgba(255,72,72,.55)",
        HIGH:"rgba(255,120,72,.45)",
        MEDIUM:"rgba(255,190,64,.40)",
        LOW:"rgba(140,200,255,.32)",
        INFO:"rgba(190,190,190,.22)",
        TRACE:"rgba(130,130,130,.18)",
      };

      let acc = 0;
      const segs = [];
      legend.innerHTML = "";
      for (const k of order){
        const v = counts[k]||0;
        if (!v) continue;
        const p = total ? (v/total)*100 : 0;
        const a0 = acc;
        const a1 = acc + p;
        acc = a1;
        segs.push(`${tint[k]} ${a0}% ${a1}%`);

        const lg = document.createElement("div");
        lg.className = "lg";
        lg.innerHTML = `<span class="dot" style="background:${tint[k]};"></span>${k}:${v}`;
        legend.appendChild(lg);
      }
      if (!segs.length){
        segs.push(`rgba(255,255,255,.10) 0% 100%`);
        legend.innerHTML = `<div class="lg" style="opacity:.7;">No counts found</div>`;
      }
      el.style.background = `conic-gradient(${segs.join(",")})`;
    }

    function pickFindingsShape(j){
      if (!j) return [];
      if (Array.isArray(j)) return j;
      if (Array.isArray(j.findings)) return j.findings;
      if (Array.isArray(j.items)) return j.items;
      if (Array.isArray(j.results)) return j.results;
      if (Array.isArray(j.data)) return j.data;
      return [];
    }

    function getField(obj, keys){
      for (const k of keys){
        if (obj && obj[k] != null) return obj[k];
      }
      return null;
    }

    function normSev(v){
      const s = (v||"").toString().toUpperCase();
      if (["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].includes(s)) return s;
      // tolerate common synonyms
      if (s === "WARNING") return "MEDIUM";
      if (s === "ERROR") return "HIGH";
      return "INFO";
    }

    function sortFindings(fs){
      const w = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};
      return fs.slice().sort((a,b)=>{
        const sa = w[normSev(getField(a,["severity","sev","level"]))] ?? 9;
        const sb = w[normSev(getField(b,["severity","sev","level"]))] ?? 9;
        if (sa !== sb) return sa - sb;
        const ta = (getField(a,["tool","scanner","engine"])||"").toString();
        const tb = (getField(b,["tool","scanner","engine"])||"").toString();
        return ta.localeCompare(tb);
      });
    }

    async function render(){
      ensureStyle();

      // wait for injected shell from previous patches
      for (let i=0;i<30;i++){
        if (ensureContainers()) break;
        await sleep(120);
      }
      if (!ensureContainers()) return;

      const meta = await fetchJSON("/api/vsp/runs?_ts=" + Date.now());
      const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!rid) return;

      // prefer gate summary
      let sum = null;
      let gateFile = "run_gate_summary.json";
      try{
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json&_ts=${Date.now()}`);
      }catch(e1){
        gateFile = "run_gate.json";
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json&_ts=${Date.now()}`);
      }

      const overall = (sum?.overall_status || sum?.overall || sum?.status || "—").toString().toUpperCase();
      const degraded = (sum?.degraded!=null) ? sum.degraded : "—";
      const updated = new Date().toLocaleString();

      const set = (id,v)=>{ const el=$(id); if(el) el.textContent = (v==null?"—":String(v)); };
      set("vsp_run_rid", rid);
      set("vsp_run_overall", overall);
      set("vsp_run_degraded", degraded);
      set("vsp_run_updated", updated);
      set("vsp_run_gatefile", gateFile);

      const aZip = $("vsp_run_zip2"), aPdf = $("vsp_run_pdf2");
      if (aZip) aZip.href = `/api/vsp/run_export_zip?rid=${encodeURIComponent(rid)}`;
      if (aPdf) aPdf.href = `/api/vsp/run_export_pdf?rid=${encodeURIComponent(rid)}`;

      // donut from counts
      const counts = normalizeCounts(sum);
      renderDonut(counts);

      // findings preview
      const rows = $("vsp_findings_rows");
      const metaEl = $("vsp_findings_meta");
      if (rows) rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">Loading findings_unified.json…</td></tr>`;

      let findings = [];
      try{
        const txt = await fetchText(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_ts=${Date.now()}`);
        const j = JSON.parse(txt);
        findings = pickFindingsShape(j);
      }catch(e){
        findings = [];
      }

      const totalFind = findings.length || 0;
      if (metaEl) metaEl.textContent = `items=${totalFind} • rid=${rid.slice(0,24)}…`;

      const top = sortFindings(findings).slice(0, 12);
      if (!rows) return;

      if (!top.length){
        rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">No findings parsed (schema unknown) — but file exists. Use Data Source tab for full view.</td></tr>`;
        console.log("[VSP][DashFull] findings parsed=0 (schema mismatch?) rid=", rid);
        return;
      }

      const tr = top.map(f=>{
        const sev = normSev(getField(f,["severity","sev","level","priority"]));
        const tool = (getField(f,["tool","scanner","engine","source"]) || "—").toString();
        const title = (getField(f,["title","name","message","desc","description","summary"]) || "—").toString();
        const rule = (getField(f,["rule_id","rule","check_id","id","cwe","owasp"]) || "").toString();
        const file = (getField(f,["path","file","file_path","location","filename"]) || "—").toString();
        const line = getField(f,["line","start_line","linenumber","row"]);
        const file2 = line!=null ? `${file}:${line}` : file;
        const t = rule ? `${title} • ${rule}` : title;
        return `<tr>
          <td>${sevBadge(sev)}</td>
          <td style="opacity:.9;">${esc(tool)}</td>
          <td style="opacity:.92;">${esc(t).slice(0,220)}</td>
          <td style="opacity:.85;font-family:ui-monospace,monospace;font-size:11.5px;">${esc(file2).slice(0,180)}</td>
        </tr>`;
      }).join("");

      rows.innerHTML = tr;

      console.log("[VSP][DashFull] ok rid=", rid, "overall=", overall, "findings=", totalFind);
    }

    // kick + periodic refresh
    const kick = ()=> render().catch(e=>console.warn("[VSP][DashFull] err", e));
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ()=> setTimeout(kick, 240));
    else setTimeout(kick, 240);

    setInterval(()=> {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      kick();
    }, 60000);

  }catch(e){
    console.warn("[VSP][DashFull] init failed", e);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended full dashboard enhancer")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Open /vsp5 and HARD reload (Ctrl+Shift+R)."
