#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dashp1v4_${TS}"
echo "[BACKUP] ${JS}.bak_dashp1v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHBOARD_P1_PANELS_V4_MULTIFINDINGS_HARD_FIX"
if marker in s:
    print("[OK] already applied:", marker)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_PANELS_V4_MULTIFINDINGS_HARD_FIX =====================
   Fix: backend may return gate_summary when asking findings_unified; V4 probes multiple paths and accepts only true findings contract.
=============================================================================================== */
(()=> {
  if (window.__vsp_dash_p1_v4) return;
  window.__vsp_dash_p1_v4 = true;

  // disable older addons (best-effort)
  window.__vsp_p1_dash_p1_panels_v1 = true;
  window.__vsp_p1_dash_p1_override_v2 = true;
  window.__vsp_dash_p1_v3_hard_fix = true;

  const TOOL_ORDER = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
  const SEV_ORDER  = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function el(tag, attrs={}, kids=[]){
    const n=document.createElement(tag);
    for (const [k,v] of Object.entries(attrs||{})){
      if (k==="class") n.className=v;
      else if (k==="html") n.innerHTML=v;
      else n.setAttribute(k, String(v));
    }
    (kids||[]).forEach(c=> n.appendChild(typeof c==="string"? document.createTextNode(c) : c));
    return n;
  }

  function cssOnce(){
    if (document.getElementById("VSP_DASH_P1_V4_CSS")) return;
    const css = `
      .vspP1v4Wrap{padding:14px 18px 56px 18px;}
      .vspP1v4Row{display:flex; gap:12px; flex-wrap:wrap;}
      .vspP1v4Card{background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:14px; padding:12px 14px; flex:1; min-width:260px;}
      .vspP1v4Card h3{margin:0 0 8px 0; font-size:12px; opacity:.85; font-weight:900;}
      .vspP1v4Muted{opacity:.78; font-size:12px;}
      .vspP1v4Mono{font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;}
      .vspP1v4Pills{display:flex; gap:8px; flex-wrap:wrap;}
      .vspP1v4Pill{display:inline-flex; align-items:center; gap:8px; padding:8px 10px; border-radius:999px;
                   border:1px solid rgba(255,255,255,0.10); background:rgba(255,255,255,0.03); cursor:pointer; user-select:none;}
      .vspP1v4Dot{width:9px;height:9px;border-radius:50%;}
      .vspP1v4Table{width:100%; border-collapse:collapse; font-size:12px;}
      .vspP1v4Table th,.vspP1v4Table td{padding:8px 8px; border-bottom:1px solid rgba(255,255,255,0.08); vertical-align:top;}
      .vspP1v4Table th{opacity:.8; text-align:left; font-weight:900;}
      .vspP1v4Err{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,0,0,0.25); background:rgba(255,0,0,0.06); font-size:12px;}
      .vspP1v4Ok{display:inline-flex; align-items:center; gap:8px; padding:6px 10px; border-radius:999px;
                border:1px solid rgba(0,220,120,0.25); background:rgba(0,220,120,0.06); font-size:12px;}
    `;
    document.head.appendChild(el("style",{id:"VSP_DASH_P1_V4_CSS", html:css}));
  }

  function normStatus(x){
    const v=String(x||"").toUpperCase();
    if (v.includes("PASS")||v==="GREEN") return "GREEN";
    if (v.includes("WARN")||v==="AMBER"||v==="YELLOW") return "AMBER";
    if (v.includes("FAIL")||v==="RED") return "RED";
    if (v.includes("MISSING")) return "MISSING";
    return v||"UNKNOWN";
  }
  function dot(status){
    const s=normStatus(status);
    let bg="rgba(200,200,200,0.8)";
    if (s==="GREEN") bg="rgba(0,220,120,0.85)";
    if (s==="AMBER") bg="rgba(255,200,0,0.85)";
    if (s==="RED") bg="rgba(255,70,70,0.85)";
    if (s==="MISSING") bg="rgba(160,160,160,0.85)";
    return el("span",{class:"vspP1v4Dot", style:"background:"+bg});
  }

  function pickRID(o){
    if (!o || typeof o!=="object") return null;
    return o.rid || o.run_id || o.latest_rid || o.id || null;
  }

  function unwrapAny(j){
    const seen=new Set();
    let cur=j;
    while(cur && typeof cur==="object" && !Array.isArray(cur) && !seen.has(cur)){
      seen.add(cur);
      const cand = cur.data ?? cur.json ?? cur.content ?? cur.payload ?? cur.body ?? cur.result ?? cur.obj ?? cur.value;
      if (cand && cand !== cur) { cur=cand; continue; }
      break;
    }
    return cur;
  }

  function normFindings(j){
    const o = (j && typeof j==="object") ? j : {};
    if (!o.meta || typeof o.meta!=="object") o.meta = {};
    if (!("findings" in o) && Array.isArray(o.items)) o.findings = o.items;
    if (o.findings && typeof o.findings==="object" && !Array.isArray(o.findings) && Array.isArray(o.findings.items)) o.findings = o.findings.items;
    if (!o.meta.counts_by_severity && o.counts_by_severity && typeof o.counts_by_severity==="object") o.meta.counts_by_severity = o.counts_by_severity;
    return o;
  }

  function isGateSummaryShape(o){
    if (!o || typeof o!=="object" || Array.isArray(o)) return false;
    // typical gate summary keys
    return ("overall" in o) && ("by_tool" in o) && ("counts_total" in o);
  }

  function isFindingsContract(o){
    if (!o || typeof o!=="object" || Array.isArray(o)) return false;
    const meta = o.meta;
    const cbs = meta && meta.counts_by_severity;
    return !!(cbs && typeof cbs==="object" && Array.isArray(o.findings));
  }

  async function fetchJSON(url){
    const res = await fetch(url, {credentials:"same-origin"});
    const txt = await res.text();
    let j; try{ j=JSON.parse(txt);}catch(e){ throw new Error("Non-JSON "+res.status); }
    if (!res.ok) throw new Error("HTTP "+res.status);
    return unwrapAny(j);
  }

  function scrapeRIDFromPage(){
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(/\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/);
    if (m && m[0]) return m[0];
    const m2 = t.match(/\bRUN_\d{8}_\d{6}\b/);
    if (m2 && m2[0]) return m2[0];
    return null;
  }

  function toolObj(gate, tool){
    const bt = gate && gate.by_tool && gate.by_tool[tool];
    const tt = gate && gate.tools && gate.tools[tool];
    const o = bt || tt || null;
    if (o && typeof o==="object"){
      return {
        status: o.status || o.overall || o.result || o.state || "UNKNOWN",
        degraded: !!o.degraded,
        reason: o.degraded_reason || o.reason || o.note || ""
      };
    }
    return {status:"UNKNOWN", degraded:false, reason:""};
  }

  function sevRank(s){
    const v=String(s||"").toUpperCase();
    const i=SEV_ORDER.indexOf(v);
    return i>=0 ? i : 999;
  }

  function normFinding(f){
    const sev = String(f.severity||f.sev||f.level||"").toUpperCase();
    const tool = f.tool || f.source || f.engine || f.detector || "";
    const title = f.title || f.message || f.rule_name || f.rule_id || f.id || "(no title)";
    const loc = (() => {
      const path = f.path || (f.location && f.location.path) || (f.file && f.file.path) || "";
      const line = f.line || (f.location && f.location.line) || (f.start && f.start.line) || "";
      return (path ? path : "(no path)") + (line ? (":" + line) : "");
    })();
    return {sev, tool, title, loc};
  }

  function cleanupOld(){
    ["vsp_p1_panels_mount_v1","vsp_p1_panels_mount_v2","vsp_p1_panels_mount_v3","vsp_p1_panels_mount_v4"].forEach(id=>{
      const n=document.getElementById(id); if (n) n.remove();
    });
    // remove old red bars if any
    Array.from(document.querySelectorAll(".vspP1Err,.vspP1v2Err,.vspP1v3Err,.vspP1v4Err")).forEach(n=>{ try{n.remove();}catch(e){} });
  }

  function findHost(){
    return document.getElementById("vsp5_root")
        || document.querySelector("main")
        || document.body;
  }

  async function loadFindings(rid){
    // Try several allowlist-safe candidates; accept only true findings contract
    const candidates = [
      "findings_unified.json",
      "reports/findings_unified.json",
      "reports/findings_unified.sarif", // (rare; if server wraps into json it will fail contract anyway)
    ];

    let last = null;
    for (const path of candidates){
      try{
        let j = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path="+encodeURIComponent(path));
        j = normFindings(j);

        if (isGateSummaryShape(j)){
          last = {path, keys:Object.keys(j||{}), note:"gate_summary_shape"};
          continue;
        }
        if (isFindingsContract(j)){
          return {ok:true, path, obj:j};
        }
        last = {path, keys:Object.keys(j||{}), note:"not_findings_contract"};
      }catch(e){
        last = {path, err:String(e.message||e)};
      }
    }
    return {ok:false, last};
  }

  async function render(){
    if (location.pathname !== "/vsp5") return;
    cssOnce();
    cleanupOld();

    const host = findHost();
    const mount = el("div",{id:"vsp_p1_panels_mount_v4", class:"vspP1v4Wrap"});
    host.appendChild(mount);

    // RID resolve: global -> scrape page -> runs
    let rid = window.__VSP_RID_LATEST_GATE_ROOT__ || window.__vsp_rid_latest_gate_root || null;
    if (!rid) rid = scrapeRIDFromPage();
    if (!rid){
      try{
        const runs = await fetchJSON("/api/vsp/runs?limit=1&offset=0");
        const arr = Array.isArray(runs) ? runs : (runs.runs || runs.items || []);
        if (Array.isArray(arr) && arr.length) rid = pickRID(arr[0]);
      }catch(e){}
    }
    if (!rid){
      mount.appendChild(el("div",{class:"vspP1v4Err"},["Cannot resolve RID (scrape+runs fallback)."]));
      return;
    }

    // gate summary must load
    let gate=null;
    try{
      gate = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=run_gate_summary.json");
    }catch(e){
      mount.appendChild(el("div",{class:"vspP1v4Err"},["Load gate_summary failed: "+String(e.message||e)]));
      return;
    }

    // findings: multi-path + contract acceptance
    const fr = await loadFindings(rid);
    if (!fr.ok){
      const info = fr.last || {};
      mount.appendChild(el("div",{class:"vspP1v4Err"},[
        "Findings not found/contract mismatch after probes. ",
        "last_path=", String(info.path||"?"), " ",
        "note=", String(info.note||""), " ",
        "keys=", String((info.keys||[]).join(",")) ,
        info.err ? (" err="+info.err) : ""
      ]));
      console.log("[VSP][DashP1V4] findings probe failed:", fr);
      return;
    }

    const findings = fr.obj;
    const meta = findings.meta || {};
    const cbs = meta.counts_by_severity;
    const arrFind = findings.findings;

    // Tool lane
    const lane = el("div",{class:"vspP1v4Card"},[
      el("h3",{},["Tool Lane (8 tools)"]),
      el("div",{class:"vspP1v4Pills"}, TOOL_ORDER.map(t=>{
        const st = toolObj(gate,t);
        const ns = normStatus(st.status);
        const pill = el("div",{class:"vspP1v4Pill", title:(st.reason||"")},[
          dot(ns),
          el("span",{class:"vspP1v4Mono", style:"font-weight:900;"},[t]),
          el("span",{class:"vspP1v4Muted"},[ns + (st.degraded?" (degraded)":"")]),
        ]);
        pill.addEventListener("click", ()=> { location.href="/runs?rid="+encodeURIComponent(rid); });
        return pill;
      }))
    ]);

    // Explain
    const reasons = [];
    const src = gate && (gate.reasons || gate.top_reasons || gate.fail_reasons);
    if (Array.isArray(src)){
      for (const x of src){
        const r = (typeof x==="string") ? x : (x.reason||x.title||"");
        if (r) reasons.push(r);
      }
    }
    if (!reasons.length){
      for (const t of TOOL_ORDER){
        const st = toolObj(gate,t);
        const ns = normStatus(st.status);
        if (ns==="RED" || st.degraded || ns==="MISSING"){
          reasons.push(`${t}: ${ns}` + (st.reason?` — ${st.reason}`:""));
        }
      }
    }
    const explain = el("div",{class:"vspP1v4Card"},[
      el("h3",{},["Explain why RED / Degraded"]),
      reasons.length
        ? el("ul",{style:"margin:0; padding-left:18px;"}, reasons.slice(0,8).map(r=>el("li",{class:"vspP1v4Muted", style:"margin:6px 0;"},[r])))
        : el("div",{class:"vspP1v4Muted"},["No reasons found in gate summary."])
    ]);

    // Top findings
    const topRows = arrFind.map(normFinding).sort((a,b)=>sevRank(a.sev)-sevRank(b.sev)).slice(0,12);
    const tbl = el("div",{class:"vspP1v4Card", style:"flex-basis:100%;"},[
      el("h3",{},["Top Findings (fix-first)"]),
      el("div",{class:"vspP1v4Ok vspP1v4Mono"},[
        "rid=", rid, " • findings=", String(arrFind.length),
        " • CRIT=", String(cbs.CRITICAL||0), " • HIGH=", String(cbs.HIGH||0),
        " • source_path=", fr.path
      ]),
      el("table",{class:"vspP1v4Table", style:"margin-top:10px;"},[
        el("thead",{},[el("tr",{},[
          el("th",{},["Severity"]), el("th",{},["Tool"]), el("th",{},["Title"]), el("th",{},["Location"])
        ])]),
        el("tbody",{}, topRows.map(r=>el("tr",{},[
          el("td",{class:"vspP1v4Mono"},[r.sev||"UNKNOWN"]),
          el("td",{class:"vspP1v4Mono"},[String(r.tool||"")]),
          el("td",{},[String(r.title||"")]),
          el("td",{class:"vspP1v4Mono vspP1v4Muted"},[String(r.loc||"")]),
        ])))
      ])
    ]);

    mount.appendChild(el("div",{class:"vspP1v4Row"},[lane, explain]));
    mount.appendChild(el("div",{class:"vspP1v4Row", style:"margin-top:12px;"},[tbl]));

    console.log("[VSP][DashP1V4] ok rid="+rid+" source_path="+fr.path+" top_findings="+topRows.length);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", render);
  else render();
})();
 /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_V4_MULTIFINDINGS_HARD_FIX ===================== */
""").strip("\n")

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

echo "[DONE] Dash P1 V4 multifindings hard fix appended."
echo "Next: restart UI then HARD refresh /vsp5 (Ctrl+Shift+R)."
