#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p1_override_v2_${TS}"
echo "[BACKUP] ${JS}.bak_p1_override_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHBOARD_P1_PANELS_OVERRIDE_V2"
if marker in s:
    print("[OK] already applied:", marker)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_PANELS_OVERRIDE_V2 =====================
   Purpose: Always render P1 panels on /vsp5 regardless of older addon state.
   Panels: Tool Lane (8), Explain, Top Findings (12), Trend (best-effort)
=================================================================================== */
(()=> {
  if (window.__vsp_p1_dash_p1_override_v2) return;
  window.__vsp_p1_dash_p1_override_v2 = true;

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
    if (document.getElementById("VSP_P1_DASH_P1_OVR_CSS_V2")) return;
    const css = `
      .vspP1v2Wrap{padding:14px 18px 40px 18px;}
      .vspP1v2Row{display:flex; gap:12px; flex-wrap:wrap;}
      .vspP1v2Card{background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:14px; padding:12px 14px; flex:1; min-width:260px;}
      .vspP1v2Card h3{margin:0 0 8px 0; font-size:12px; opacity:.85; font-weight:800;}
      .vspP1v2Muted{opacity:.78; font-size:12px;}
      .vspP1v2Mono{font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;}
      .vspP1v2Pills{display:flex; gap:8px; flex-wrap:wrap;}
      .vspP1v2Pill{display:inline-flex; align-items:center; gap:8px; padding:8px 10px; border-radius:999px;
                   border:1px solid rgba(255,255,255,0.10); background:rgba(255,255,255,0.03); cursor:pointer; user-select:none;}
      .vspP1v2Dot{width:9px;height:9px;border-radius:50%;}
      .vspP1v2Table{width:100%; border-collapse:collapse; font-size:12px;}
      .vspP1v2Table th,.vspP1v2Table td{padding:8px 8px; border-bottom:1px solid rgba(255,255,255,0.08); vertical-align:top;}
      .vspP1v2Table th{opacity:.8; text-align:left; font-weight:900;}
      .vspP1v2Bars{display:flex; gap:6px; align-items:flex-end; height:64px; padding:6px 0;}
      .vspP1v2Bar{flex:1; background:rgba(255,255,255,0.10); border:1px solid rgba(255,255,255,0.10); border-radius:8px;}
      .vspP1v2Err{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,0,0,0.25); background:rgba(255,0,0,0.06); font-size:12px;}
      .vspP1v2OkTag{display:inline-flex; align-items:center; gap:8px; padding:6px 10px; border-radius:999px;
                   border:1px solid rgba(0,220,120,0.25); background:rgba(0,220,120,0.06); font-size:12px;}
    `;
    document.head.appendChild(el("style",{id:"VSP_P1_DASH_P1_OVR_CSS_V2", html:css}));
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
    return el("span",{class:"vspP1v2Dot", style:"background:"+bg});
  }

  async function fetchJSON(url){
    const res = await fetch(url, {credentials:"same-origin"});
    const txt = await res.text();
    let j; try{ j=JSON.parse(txt);}catch(e){ throw new Error("Non-JSON "+res.status); }
    if (!res.ok) throw new Error("HTTP "+res.status);

    // unwrap common wrappers
    const seen = new Set();
    function unwrapAny(x){
      let cur = x;
      while (cur && typeof cur==="object" && !Array.isArray(cur) && !seen.has(cur)){
        seen.add(cur);
        const cand = cur.data ?? cur.json ?? cur.content ?? cur.payload ?? cur.body ?? cur.result ?? cur.obj ?? cur.value;
        if (cand && cand !== cur) { cur = cand; continue; }
        break;
      }
      return cur;
    }
    j = unwrapAny(j);

    // normalize findings shapes
    if (j && typeof j==="object" && !Array.isArray(j)){
      if (!j.meta || typeof j.meta!=="object") j.meta = {};
      if (!("findings" in j) && Array.isArray(j.items)) j.findings = j.items;
      if (j.findings && typeof j.findings==="object" && !Array.isArray(j.findings) && Array.isArray(j.findings.items)) j.findings = j.findings.items;
      if (!j.meta.counts_by_severity && j.counts_by_severity && typeof j.counts_by_severity==="object") j.meta.counts_by_severity = j.counts_by_severity;
    }
    return j;
  }

  function pickRID(o){
    if (!o || typeof o!=="object") return null;
    return o.rid || o.run_id || o.latest_rid || o.id || null;
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

  function findHost(){
    // try common containers first; fallback to body
    return document.getElementById("vsp_dashboard_mount_v1")
        || document.getElementById("vsp5_root")
        || document.querySelector("main")
        || document.querySelector(".container")
        || document.body;
  }

  async function render(){
    if (location && location.pathname && location.pathname !== "/vsp5") return;

    cssOnce();
    const host = findHost();
    if (!host) return;

    let mount = document.getElementById("vsp_p1_panels_mount_v2");
    if (!mount){
      mount = el("div",{id:"vsp_p1_panels_mount_v2", class:"vspP1v2Wrap"});
      host.appendChild(mount);
    }

    // RID resolve: rid_latest -> runs fallback (do NOT use the buggy spaced endpoint)
    let rid = null;
    try{
      const o = await fetchJSON("/api/vsp/rid_latest_gate_root");
      rid = pickRID(o);
    }catch(e1){
      try{
        const runs = await fetchJSON("/api/vsp/runs?limit=1&offset=0");
        const arr = Array.isArray(runs) ? runs : (runs.runs || runs.items || []);
        if (Array.isArray(arr) && arr.length) rid = pickRID(arr[0]);
      }catch(e2){}
    }

    if (!rid){
      mount.innerHTML = "";
      mount.appendChild(el("div",{class:"vspP1v2Err"},["Cannot resolve RID for dashboard."]));
      return;
    }

    let gate, findings;
    try{
      gate = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=run_gate_summary.json");
      findings = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=findings_unified.json");
    }catch(e){
      mount.innerHTML = "";
      mount.appendChild(el("div",{class:"vspP1v2Err"},["Load failed: "+String(e.message||e)]));
      return;
    }

    const meta = (findings && findings.meta) || {};
    const cbs = meta.counts_by_severity;
    const arrFind = findings && findings.findings;

    if (!cbs || typeof cbs!=="object" || !Array.isArray(arrFind)){
      mount.innerHTML = "";
      mount.appendChild(el("div",{class:"vspP1v2Err"},[
        "Contract mismatch after normalize. keys=" + Object.keys(findings||{}).join(",")
      ]));
      return;
    }

    // Tool lane
    const lane = el("div",{class:"vspP1v2Card"},[
      el("h3",{},["Tool Lane (8 tools)"]),
      el("div",{class:"vspP1v2Pills"}, TOOL_ORDER.map(t=>{
        const st = toolObj(gate,t);
        const ns = normStatus(st.status);
        const pill = el("div",{class:"vspP1v2Pill", title:(st.reason||"")},[
          dot(ns),
          el("span",{class:"vspP1v2Mono", style:"font-weight:900;"},[t]),
          el("span",{class:"vspP1v2Muted"},[ns + (st.degraded?" (degraded)":"")]),
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
    const explain = el("div",{class:"vspP1v2Card"},[
      el("h3",{},["Explain why RED / Degraded"]),
      reasons.length
        ? el("ul",{style:"margin:0; padding-left:18px;"}, reasons.slice(0,8).map(r=>el("li",{class:"vspP1v2Muted", style:"margin:6px 0;"},[r])))
        : el("div",{class:"vspP1v2Muted"},["No reasons found in gate summary."])
    ]);

    // Trend
    const trend = el("div",{class:"vspP1v2Card"},[
      el("h3",{},["Trend (last 10 runs)"]),
      el("div",{class:"vspP1v2Muted", id:"vspP1v2TrendNote"},["Loading runs…"]),
      el("div",{class:"vspP1v2Bars", id:"vspP1v2Bars"},[])
    ]);

    // Top findings
    const topRows = arrFind.map(normFinding).sort((a,b)=>sevRank(a.sev)-sevRank(b.sev)).slice(0,12);
    const tbl = el("div",{class:"vspP1v2Card", style:"flex-basis:100%;"},[
      el("h3",{},["Top Findings (fix-first)"]),
      el("div",{class:"vspP1v2OkTag vspP1v2Mono"},[
        "rid=", rid, " • findings=", String(arrFind.length), " • C/H=", String((cbs.CRITICAL||0)+"/"+(cbs.HIGH||0))
      ]),
      el("table",{class:"vspP1v2Table", style:"margin-top:10px;"},[
        el("thead",{},[el("tr",{},[
          el("th",{},["Severity"]), el("th",{},["Tool"]), el("th",{},["Title"]), el("th",{},["Location"])
        ])]),
        el("tbody",{}, topRows.map(r=>el("tr",{},[
          el("td",{class:"vspP1v2Mono"},[r.sev||"UNKNOWN"]),
          el("td",{class:"vspP1v2Mono"},[String(r.tool||"")]),
          el("td",{},[String(r.title||"")]),
          el("td",{class:"vspP1v2Mono vspP1v2Muted"},[String(r.loc||"")]),
        ])))
      ])
    ]);

    mount.innerHTML = "";
    mount.appendChild(el("div",{class:"vspP1v2Row"},[lane, explain, trend]));
    mount.appendChild(el("div",{class:"vspP1v2Row", style:"margin-top:12px;"},[tbl]));

    // fill trend best-effort
    (async ()=>{
      const note = mount.querySelector("#vspP1v2TrendNote");
      const bars = mount.querySelector("#vspP1v2Bars");
      try{
        const runs = await fetchJSON("/api/vsp/runs?limit=10");
        const arr = Array.isArray(runs) ? runs : (runs.runs || runs.items || []);
        if (!Array.isArray(arr) || !arr.length){
          note.textContent = "No runs data from backend.";
          return;
        }
        const pts = arr.slice(0,10).reverse().map(x=>{
          const c = x.counts_by_severity || (x.meta && x.meta.counts_by_severity) || null;
          const ch = c ? (Number(c.CRITICAL||0) + Number(c.HIGH||0)) : 0;
          return {ch};
        });
        const max = Math.max(1, ...pts.map(p=>p.ch));
        bars.innerHTML="";
        for (const p of pts){
          const h = Math.max(6, Math.round((p.ch/max)*64));
          bars.appendChild(el("div",{class:"vspP1v2Bar", style:"height:"+h+"px", title:"C+H="+p.ch}));
        }
        note.textContent = "Bar = (CRITICAL+HIGH) (best-effort).";
      }catch(e){
        note.textContent = "Trend unavailable: "+String(e.message||e);
      }
    })();

    console.log("[VSP][DashP1PanelsOverrideV2] ok rid="+rid+" top_findings="+topRows.length);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", render);
  else render();
})();
 /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_OVERRIDE_V2 ===================== */
""").strip("\n")

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended override:", marker)
PY

echo "[DONE] P1 panels override V2 appended."
echo "Next: restart UI then HARD refresh /vsp5."
