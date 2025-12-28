#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p1v7_${TS}"
echo "[BACKUP] ${JS}.bak_p1v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASHBOARD_P1_PANELS_V7_STABLE_FIX"
if MARK in s:
    print("[OK] already applied:", MARK)
    raise SystemExit(0)

helpers = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_HELPERS_DEF_V1 ===================== */
(()=> {
  if (window.__vsp_p1_helpers_def_v1) return;
  window.__vsp_p1_helpers_def_v1 = true;

  window.__vsp_p1_normFindingsPayload = function(payload){
    // Accept: {meta,findings} OR {ok:true, data:{meta,findings}} OR {data:{...}} OR raw array
    try{
      if (!payload) return null;
      if (Array.isArray(payload)) return { meta: { counts_by_severity: {} }, findings: payload };
      if (typeof payload !== "object") return null;

      if (payload.meta && Array.isArray(payload.findings)) return payload;
      if (payload.data && payload.data.meta && Array.isArray(payload.data.findings)) return payload.data;
      if (payload.ok && payload.data && payload.data.meta && Array.isArray(payload.data.findings)) return payload.data;
      if (payload.findings_unified && payload.findings_unified.meta && Array.isArray(payload.findings_unified.findings)) return payload.findings_unified;

      // Sometimes wrapped: {meta:{...}, items:[...]}
      if (payload.meta and Array.isArray(payload.items)) return { meta: payload.meta, findings: payload.items };

      return null;
    }catch(e){ return null; }
  };

  window.__vsp_p1_xhrText = function(url){
    return new Promise((resolve,reject)=>{
      const x = new XMLHttpRequest();
      x.open("GET", url, true);
      x.responseType = "text";
      x.withCredentials = true;
      x.onreadystatechange = ()=>{
        if (x.readyState !== 4) return;
        if (x.status < 200 || x.status >= 300) return reject(new Error("HTTP "+x.status));
        resolve(x.responseText || "");
      };
      x.onerror = ()=> reject(new Error("XHR error"));
      x.send();
    });
  };

  window.__vsp_p1_xhrJSON = async function(url){
    const t = await window.__vsp_p1_xhrText(url);
    return JSON.parse(t);
  };

  window.__vsp_p1_findRIDFromPage = function(){
    // parse from subtitle "Tool truth (gate_root): RID"
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(/\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/);
    if (m) return m[0];
    const m2 = t.match(/\bRUN_\d{8}_\d{6}\b/);
    return m2 ? m2[0] : null;
  };

  console.log("[VSP][DashP1HelpersV1] installed");
})();
/* ===================== /VSP_P1_DASHBOARD_P1_HELPERS_DEF_V1 ===================== */
""").lstrip("\n")

v7 = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_PANELS_V7_STABLE_FIX =====================
   Stable commercial renderer:
   - Uses XHR (no fetch wrapper issues)
   - Reads fixed contracts:
     run_gate_summary.json -> overall/degraded/by_tool/top_reasons
     findings_unified.json -> meta.counts_by_severity + findings[]
   - Renders Tool Lane + Explain + Top Findings into empty area
=============================================================================== */
(()=> {
  if (window.__vsp_p1_panels_v7) return;
  window.__vsp_p1_panels_v7 = true;

  function sevRank(s){
    const o = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};
    return (s in o) ? o[s] : 99;
  }
  function pick(o, keys, d=null){
    for (const k of keys){ if (o && typeof o==="object" && k in o) return o[k]; }
    return d;
  }
  function esc(x){ return String(x??"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c])); }

  async function resolveRID(){
    // Prefer any global gate_root rid if exists
    const g = window.__VSP_GATE_ROOT_RID__ || window.__vsp_gate_root_rid || window.__vsp_gate_root || null;
    if (g) return g;

    // Try runs API (works even if rid_latest_gate_root missing)
    try{
      const j = await window.__vsp_p1_xhrJSON(location.origin + "/api/vsp/runs?limit=1&offset=0");
      const raw = JSON.stringify(j);
      const m = raw.match(/\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/);
      if (m) return m[0];
      const m2 = raw.match(/\bRUN_\d{8}_\d{6}\b/);
      if (m2) return m2[0];
    }catch(e){}

    // Fallback: parse visible text
    return window.__vsp_p1_findRIDFromPage();
  }

  function ensureHost(){
    let host = document.getElementById("vsp_p1_panels_v7_host");
    if (host) return host;

    // Put into the big empty area below the top cards
    const anchor = document.querySelector(".vsp5_body") || document.querySelector("main") || document.body;
    host = document.createElement("div");
    host.id = "vsp_p1_panels_v7_host";
    host.style.margin = "14px 0 0 0";
    host.style.padding = "12px";
    host.style.borderRadius = "12px";
    host.style.border = "1px solid rgba(255,255,255,0.06)";
    host.style.background = "rgba(255,255,255,0.02)";
    host.innerHTML = `<div style="display:flex;align-items:center;gap:10px;justify-content:space-between;">
        <div style="font-weight:700;">Commercial Panels</div>
        <div id="vsp_p1_v7_meta" style="opacity:.75;font-size:12px;"></div>
      </div>
      <div id="vsp_p1_v7_err" style="display:none;margin-top:10px;padding:10px;border-radius:10px;border:1px solid rgba(255,0,80,.35);background:rgba(255,0,80,.08);"></div>
      <div id="vsp_p1_v7_grid" style="margin-top:10px;display:grid;grid-template-columns:1.1fr .9fr;gap:12px;"></div>`;
    anchor.appendChild(host);
    return host;
  }

  function showErr(msg){
    const el = document.getElementById("vsp_p1_v7_err");
    if (!el) return;
    el.style.display = "block";
    el.textContent = String(msg||"error");
  }

  function renderToolLane(byTool){
    const tools = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
    const pills = tools.map(t=>{
      const st = (byTool && byTool[t] && (byTool[t].status||byTool[t])) || "MISSING";
      const sev = String(st).toUpperCase();
      const bg = (sev==="GREEN")?"rgba(0,255,140,.10)":(sev==="AMBER")?"rgba(255,190,0,.10)":(sev==="RED")?"rgba(255,80,120,.10)":"rgba(255,255,255,.06)";
      const bd = (sev==="GREEN")?"rgba(0,255,140,.25)":(sev==="AMBER")?"rgba(255,190,0,.25)":(sev==="RED")?"rgba(255,80,120,.25)":"rgba(255,255,255,.12)";
      return `<div style="padding:8px 10px;border-radius:999px;border:1px solid ${bd};background:${bg};display:flex;gap:8px;align-items:center;">
        <div style="font-weight:700;">${esc(t)}</div>
        <div style="opacity:.85;">${esc(sev)}</div>
      </div>`;
    }).join("");
    return `<div style="border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:12px;">
      <div style="font-weight:700;margin-bottom:10px;">Tool Lane (8 tools)</div>
      <div style="display:flex;flex-wrap:wrap;gap:8px;">${pills}</div>
    </div>`;
  }

  function renderExplain(topReasons, overall){
    const items = (Array.isArray(topReasons)?topReasons:[]).slice(0,6).map((x,i)=>{
      const t = (typeof x==="string") ? x : (x && (x.title||x.reason||x.msg||JSON.stringify(x))) ;
      return `<li style="margin:6px 0;">${esc(t||("reason#"+(i+1)))}</li>`;
    }).join("");
    return `<div style="border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:12px;">
      <div style="font-weight:700;margin-bottom:8px;">Explain why ${esc(overall||"")}</div>
      <ol style="margin:0;padding-left:18px;opacity:.92;">${items || "<li>No reasons provided</li>"}</ol>
    </div>`;
  }

  function renderTopFindings(findings){
    const arr = Array.isArray(findings)?findings:[];
    // normalize fields
    const norm = arr.map(f=>{
      const sev = (f.severity||f.sev||f.level||"INFO").toUpperCase();
      const tool = (f.tool||f.source||f.engine||"").toUpperCase();
      const title = f.title||f.message||f.rule_name||f.rule_id||"finding";
      const loc = f.location||f.path||f.file||f.uri||f.artifact||"";
      return {sev,tool,title,loc, raw:f};
    }).sort((a,b)=>sevRank(a.sev)-sevRank(b.sev)).slice(0,12);

    const rows = norm.map(x=>{
      return `<tr>
        <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06);white-space:nowrap;">${esc(x.sev)}</td>
        <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06);white-space:nowrap;opacity:.9;">${esc(x.tool)}</td>
        <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06);">${esc(x.title)}</td>
        <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06);opacity:.8;">${esc(x.loc)}</td>
      </tr>`;
    }).join("");

    return `<div style="border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:12px;">
      <div style="font-weight:700;margin-bottom:10px;">Top Findings (fix-first)</div>
      <div style="overflow:auto;">
        <table style="width:100%;border-collapse:collapse;font-size:12.5px;">
          <thead><tr style="opacity:.85;">
            <th style="text-align:left;padding:8px;">Severity</th>
            <th style="text-align:left;padding:8px;">Tool</th>
            <th style="text-align:left;padding:8px;">Title</th>
            <th style="text-align:left;padding:8px;">Location</th>
          </tr></thead>
          <tbody>${rows || ""}</tbody>
        </table>
      </div>
    </div>`;
  }

  async function run(){
    ensureHost();
    const metaEl = document.getElementById("vsp_p1_v7_meta");
    const grid = document.getElementById("vsp_p1_v7_grid");

    const rid = await resolveRID();
    if (metaEl) metaEl.textContent = rid ? ("RID: "+rid) : "RID: (unresolved)";
    if (!rid) return showErr("Cannot resolve RID (runs + page scan).");

    try{
      const gateUrl = location.origin + "/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=run_gate_summary.json";
      const finUrl  = location.origin + "/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=findings_unified.json";
      const gate = await window.__vsp_p1_xhrJSON(gateUrl);
      const finRaw = await window.__vsp_p1_xhrJSON(finUrl);
      const fin = window.__vsp_p1_normFindingsPayload(finRaw);

      const overall = pick(gate, ["overall_status","overall"], "UNKNOWN");
      const topReasons = pick(gate, ["top_reasons","reasons","why","summary_reasons"], []);
      const byTool = pick(gate, ["by_tool","tools","tool_status"], {});

      if (!fin) return showErr("Findings contract mismatch (expected meta+findings).");

      const htmlLeft = renderToolLane(byTool) + `<div style="height:12px;"></div>` + renderExplain(topReasons, overall);
      const htmlRight = renderTopFindings(fin.findings);

      if (grid){
        grid.innerHTML = `<div>${htmlLeft}</div><div>${htmlRight}</div>`;
      }
      console.log("[VSP][DashP1V7] rendered ok rid=", rid);
    }catch(e){
      console.error("[VSP][DashP1V7] error", e);
      showErr("DashP1V7 failed: " + (e && e.message ? e.message : String(e)));
    }
  }

  // delay to avoid racing existing renderers
  setTimeout(run, 250);
})();
 /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_V7_STABLE_FIX ===================== */
""").lstrip("\n")

# prepend helpers (so old V3/V4/V5 refs won't crash anymore)
# append V7 renderer at end
p.write_text(helpers + "\n\n" + s + "\n\n" + v7 + "\n", encoding="utf-8")
print("[OK] applied:", MARK)
PY

echo "[DONE] Dash P1 V7 stable fix applied."
echo "Next: restart UI then HARD refresh /vsp5 (Ctrl+Shift+R)."
