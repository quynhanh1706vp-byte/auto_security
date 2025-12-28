#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p1_panels_${TS}"
echo "[BACKUP] ${JS}.bak_p1_panels_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHBOARD_P1_PANELS_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_PANELS_V1 =====================
   Adds: Tool Lane (8), Explain why RED, Top Findings, Trend (10 runs best-effort)
   Uses commercial truth:
     - /api/vsp/rid_latest_gate_root
     - /api/vsp/run_file_allow?rid=...&path=run_gate_summary.json
     - /api/vsp/run_file_allow?rid=...&path=findings_unified.json
   Strict-ish: if findings.meta.counts_by_severity missing => show contract mismatch box.
========================================================================= */
(()=> {
  if (window.__vsp_p1_dash_p1_panels_v1) return;
  window.__vsp_p1_dash_p1_panels_v1 = true;

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
    if (document.getElementById("VSP_P1_DASH_P1_PANELS_CSS_V1")) return;
    const css = `
      .vspP1Wrap{padding:14px 0 0 0;}
      .vspP1Row{display:flex; gap:12px; flex-wrap:wrap;}
      .vspP1Card{background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:14px; padding:12px 14px; flex:1; min-width:260px;}
      .vspP1Card h3{margin:0 0 8px 0; font-size:12px; opacity:.85; font-weight:700;}
      .vspP1Muted{opacity:.78; font-size:12px;}
      .vspP1Mono{font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;}
      .vspP1Pills{display:flex; gap:8px; flex-wrap:wrap;}
      .vspP1Pill{display:inline-flex; align-items:center; gap:8px; padding:8px 10px; border-radius:999px;
                 border:1px solid rgba(255,255,255,0.10); background:rgba(255,255,255,0.03); cursor:pointer; user-select:none;}
      .vspP1Dot{width:9px;height:9px;border-radius:50%;}
      .vspP1Table{width:100%; border-collapse:collapse; font-size:12px;}
      .vspP1Table th,.vspP1Table td{padding:8px 8px; border-bottom:1px solid rgba(255,255,255,0.08); vertical-align:top;}
      .vspP1Table th{opacity:.8; text-align:left; font-weight:800;}
      .vspP1Bars{display:flex; gap:6px; align-items:flex-end; height:64px; padding:6px 0;}
      .vspP1Bar{flex:1; background:rgba(255,255,255,0.10); border:1px solid rgba(255,255,255,0.10); border-radius:8px;}
      .vspP1Warn{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,200,0,0.25); background:rgba(255,200,0,0.06); font-size:12px;}
      .vspP1Err{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,0,0,0.25); background:rgba(255,0,0,0.06); font-size:12px;}
    `;
    document.head.appendChild(el("style",{id:"VSP_P1_DASH_P1_PANELS_CSS_V1", html:css}));
  }

  async function fetchJSON(url){
    const res = await fetch(url, {credentials:"same-origin"});
    const txt = await res.text();
    let j; try{ j=JSON.parse(txt);}catch(e){ throw new Error("Non-JSON "+res.status); }
    if (!res.ok) throw new Error("HTTP "+res.status);
    // unwrap {ok:true,data:{...}} if present
    if (j && typeof j==="object" && j.data && typeof j.data==="object") return j.data;
    return j;
  }

  function pickRID(o){
    if (!o || typeof o!=="object") return null;
    return o.rid || o.run_id || o.latest_rid || o.id || null;
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
    return el("span",{class:"vspP1Dot", style:"background:"+bg});
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

  async function main(){
    cssOnce();

    // mount under existing dashboard area
    const host = document.getElementById("vsp5_root") || document.querySelector("main") || document.body;
    if (!host) return;

    let mount = document.getElementById("vsp_p1_panels_mount_v1");
    if (!mount){
      mount = el("div",{id:"vsp_p1_panels_mount_v1", class:"vspP1Wrap"});
      host.appendChild(mount);
    }

    let rid = window.__VSP_RID_LATEST_GATE_ROOT__ || window.__vsp_rid_latest_gate_root || null;
    if (!rid){
      try{
        const o = await fetchJSON("/api/vsp/rid_latest_gate_root");
        rid = pickRID(o);
      }catch(e){
        mount.innerHTML="";
        mount.appendChild(el("div",{class:"vspP1Err"},["Cannot resolve rid_latest_gate_root."]));
        return;
      }
    }

    let gate, findings;
    try{
      gate = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=run_gate_summary.json");
      findings = await fetchJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=findings_unified.json");
    }catch(e){
      mount.innerHTML="";
      mount.appendChild(el("div",{class:"vspP1Err"},["Load failed: ", String(e.message||e)]));
      return;
    }

    const meta = (findings && findings.meta) || {};
    const cbs = meta.counts_by_severity;
    if (!cbs || typeof cbs!=="object" || !Array.isArray(findings.findings)){
      mount.innerHTML="";
      mount.appendChild(el("div",{class:"vspP1Err"},[
        "Data contract mismatch: require findings.meta.counts_by_severity + findings.findings[]"
      ]));
      return;
    }

    // TOOL LANE
    const lane = el("div",{class:"vspP1Card"},[
      el("h3",{},["Tool Lane (8 tools)"]),
      el("div",{class:"vspP1Pills"}, TOOL_ORDER.map(t=>{
        const st = toolObj(gate, t);
        const ns = normStatus(st.status);
        const pill = el("div",{class:"vspP1Pill", title:(st.reason||"")},[
          dot(ns),
          el("span",{class:"vspP1Mono", style:"font-weight:900;"},[t]),
          el("span",{class:"vspP1Muted"},[ns + (st.degraded?" (degraded)":"")]),
        ]);
        pill.addEventListener("click", ()=> { location.href="/runs?rid="+encodeURIComponent(rid); });
        return pill;
      }))
    ]);

    // EXPLAIN WHY RED
    const reasons = [];
    const src = gate.reasons || gate.top_reasons || gate.fail_reasons;
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
    const explain = el("div",{class:"vspP1Card"},[
      el("h3",{},["Explain why RED / Degraded"]),
      reasons.length
        ? el("ul",{style:"margin:0; padding-left:18px;"}, reasons.slice(0,8).map(r=>el("li",{class:"vspP1Muted", style:"margin:6px 0;"},[r])))
        : el("div",{class:"vspP1Muted"},["No reasons found in gate summary."])
    ]);

    // TOP FINDINGS
    const topRows = findings.findings.map(normFinding).sort((a,b)=>sevRank(a.sev)-sevRank(b.sev)).slice(0,12);
    const tbl = el("div",{class:"vspP1Card", style:"flex-basis:100%;"},[
      el("h3",{},["Top Findings (fix-first)"]),
      el("table",{class:"vspP1Table"},[
        el("thead",{},[el("tr",{},[
          el("th",{},["Severity"]), el("th",{},["Tool"]), el("th",{},["Title"]), el("th",{},["Location"])
        ])]),
        el("tbody",{}, topRows.map(r=>el("tr",{},[
          el("td",{class:"vspP1Mono"},[r.sev||"UNKNOWN"]),
          el("td",{class:"vspP1Mono"},[String(r.tool||"")]),
          el("td",{},[String(r.title||"")]),
          el("td",{class:"vspP1Mono vspP1Muted"},[String(r.loc||"")]),
        ])))
      ])
    ]);

    // TREND (best-effort)
    const trend = el("div",{class:"vspP1Card"},[
      el("h3",{},["Trend (last 10 runs)"]),
      el("div",{class:"vspP1Muted", id:"vspP1TrendNote"},["Loading runs…"]),
      el("div",{class:"vspP1Bars", id:"vspP1Bars"},[])
    ]);

    // AUDIT HINT
    const audit = el("div",{class:"vspP1Card"},[
      el("h3",{},["Audit / ISO readiness (quick)"]),
      el("div",{class:"vspP1Warn"},[
        "ISO mapping is P1+ (needs rule_id→control table). For now: show evidence presence + honest hints."
      ]),
      el("div",{class:"vspP1Muted", style:"margin-top:8px;"},[
        "Hint: A.5 Access control • A.8 Asset mgmt • A.8.9 Config mgmt (placeholder until mapping is real)."
      ])
    ]);

    mount.innerHTML = "";
    mount.appendChild(el("div",{class:"vspP1Row"},[lane, explain, trend]));
    mount.appendChild(el("div",{class:"vspP1Row", style:"margin-top:12px;"},[tbl]));
    mount.appendChild(el("div",{class:"vspP1Row", style:"margin-top:12px;"},[audit]));

    // fill trend
    (async ()=>{
      const note = mount.querySelector("#vspP1TrendNote");
      const bars = mount.querySelector("#vspP1Bars");
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
          bars.appendChild(el("div",{class:"vspP1Bar", style:"height:"+h+"px", title:"C+H="+p.ch}));
        }
        note.textContent = "Bar = (CRITICAL+HIGH) (best-effort).";
      }catch(e){
        note.textContent = "Trend unavailable: "+String(e.message||e);
      }
    })();

    console.log("[VSP][DashP1PanelsV1] ok rid="+rid+" top_findings="+topRows.length);
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
 /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_V1 ===================== */
""").strip("\n")

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

echo "[DONE] applied P1 panels into GateStoryV1."
echo "Next: restart UI then hard refresh /vsp5."
