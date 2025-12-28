#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dashp1v6_${TS}"
echo "[BACKUP] ${JS}.bak_dashp1v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHBOARD_P1_PANELS_V6_XHR_HARD_FIX"
if marker in s:
    print("[OK] already applied:", marker)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASHBOARD_P1_PANELS_V6_XHR_HARD_FIX =====================
   Fix: fetch() body stream already read by global wrappers => use XHR for all API calls.
======================================================================================== */
(()=> {
  if (window.__vsp_dash_p1_v6_xhr) return;
  window.__vsp_dash_p1_v6_xhr = true;

  // disable older addons best-effort
  window.__vsp_dash_p1_v5_ridwait = true;
  window.__vsp_dash_p1_v4 = true;
  window.__vsp_dash_p1_v3_hard_fix = true;

  const TOOL_ORDER = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
  const SEV_ORDER  = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
  const RID_RE  = /\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/;
  const RID_RE2 = /\bRUN_\d{8}_\d{6}\b/;

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
    if (document.getElementById("VSP_DASH_P1_V6_CSS")) return;
    const css = `
      .vspP1v6Wrap{padding:14px 18px 56px 18px;}
      .vspP1v6Row{display:flex; gap:12px; flex-wrap:wrap;}
      .vspP1v6Card{background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.08); border-radius:14px; padding:12px 14px; flex:1; min-width:260px;}
      .vspP1v6Card h3{margin:0 0 8px 0; font-size:12px; opacity:.85; font-weight:900;}
      .vspP1v6Muted{opacity:.78; font-size:12px;}
      .vspP1v6Mono{font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace;}
      .vspP1v6Pills{display:flex; gap:8px; flex-wrap:wrap;}
      .vspP1v6Pill{display:inline-flex; align-items:center; gap:8px; padding:8px 10px; border-radius:999px;
                   border:1px solid rgba(255,255,255,0.10); background:rgba(255,255,255,0.03); cursor:pointer; user-select:none;}
      .vspP1v6Dot{width:9px;height:9px;border-radius:50%;}
      .vspP1v6Table{width:100%; border-collapse:collapse; font-size:12px;}
      .vspP1v6Table th,.vspP1v6Table td{padding:8px 8px; border-bottom:1px solid rgba(255,255,255,0.08); vertical-align:top;}
      .vspP1v6Table th{opacity:.8; text-align:left; font-weight:900;}
      .vspP1v6Err{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,0,0,0.25); background:rgba(255,0,0,0.06); font-size:12px;}
      .vspP1v6Wait{padding:10px 12px; border-radius:12px; border:1px solid rgba(255,200,0,0.25); background:rgba(255,200,0,0.06); font-size:12px;}
      .vspP1v6Ok{display:inline-flex; align-items:center; gap:8px; padding:6px 10px; border-radius:999px;
                border:1px solid rgba(0,220,120,0.25); background:rgba(0,220,120,0.06); font-size:12px;}
    `;
    document.head.appendChild(el("style",{id:"VSP_DASH_P1_V6_CSS", html:css}));
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
    return el("span",{class:"vspP1v6Dot", style:"background:"+bg});
  }

  // ---- XHR JSON (bypass fetch wrappers) ----
  function xhrJSON(url){
    return new Promise((resolve,reject)=>{
      const x = new XMLHttpRequest();
      x.open("GET", url, true);
      x.responseType = "text";
      x.withCredentials = true;
      x.onreadystatechange = ()=>{
        if (x.readyState !== 4) return;
        if (x.status < 200 || x.status >= 300){
          return reject(new Error("HTTP "+x.status));
        }
        try{
          resolve(JSON.parse(x.responseText));
        }catch(e){
          reject(new Error("Non-JSON"));
        }
      };
      x.onerror = ()=> reject(new Error("XHR error"));
      x.send();
    });
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
    return !!(o && typeof o==="object" && !Array.isArray(o) && ("overall" in o) && ("by_tool" in o) && ("counts_total" in o));
  }
  function isFindingsContract(o){
    return !!(o && typeof o==="object" && !Array.isArray(o) && o.meta && o.meta.counts_by_severity && Array.isArray(o.findings));
  }

  function scrapeRIDFromDOM(){
    const t = (document.body && (document.body.innerText||"")) || "";
    const m = t.match(RID_RE);
    if (m && m[0]) return m[0];
    const m2 = t.match(RID_RE2);
    if (m2 && m2[0]) return m2[0];
    return null;
  }

  function findRIDDeep(obj, depth=0){
    if (depth>7) return null;
    if (typeof obj==="string"){
      const m=obj.match(RID_RE); if (m && m[0]) return m[0];
      const m2=obj.match(RID_RE2); if (m2 && m2[0]) return m2[0];
      return null;
    }
    if (!obj || typeof obj!=="object") return null;
    if (Array.isArray(obj)){
      for (const x of obj){ const r=findRIDDeep(x, depth+1); if (r) return r; }
      return null;
    }
    for (const k of Object.keys(obj)){
      const r=findRIDDeep(obj[k], depth+1);
      if (r) return r;
    }
    return null;
  }

  async function resolveRIDWait(mount){
    const started = Date.now();
    const maxMs = 12000;
    const stepMs = 500;

    while (Date.now()-started < maxMs){
      // 1) dom (after gate story render)
      const ridDom = scrapeRIDFromDOM();
      if (ridDom) return ridDom;

      // 2) deep scan runs (XHR)
      try{
        const runs = unwrapAny(await xhrJSON("/api/vsp/runs?limit=5&offset=0"));
        const rid = findRIDDeep(runs);
        if (rid) return rid;
      }catch(e){}

      mount.textContent = "";
      mount.appendChild(el("div",{class:"vspP1v6Wait"},[
        "Waiting RID... ",
        el("span",{class:"vspP1v6Mono"},[String(Math.round((Date.now()-started)/100)/10)+"s"]),
        " (DOM + runs deep scan)"
      ]));
      await new Promise(r=>setTimeout(r, stepMs));
    }
    return null;
  }

  async function loadFindings(rid){
    const candidates = ["findings_unified.json","reports/findings_unified.json"];
    let last=null;
    for (const path of candidates){
      try{
        let j = unwrapAny(await xhrJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path="+encodeURIComponent(path)));
        j = normFindings(j);
        if (isGateSummaryShape(j)){ last={path, note:"gate_summary_shape", keys:Object.keys(j||{})}; continue; }
        if (isFindingsContract(j)) return {ok:true, path, obj:j};
        last={path, note:"not_findings_contract", keys:Object.keys(j||{})};
      }catch(e){
        last={path, err:String(e.message||e)};
      }
    }
    return {ok:false, last};
  }

  function toolObj(gate, tool){
    const bt = gate && gate.by_tool && gate.by_tool[tool];
    const tt = gate && gate.tools && gate.tools[tool];
    const o = bt || tt || null;
    if (o && typeof o==="object"){
      return { status: o.status || o.overall || o.result || o.state || "UNKNOWN",
               degraded: !!o.degraded,
               reason: o.degraded_reason || o.reason || o.note || "" };
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

  function cleanup(){
    ["vsp_p1_panels_mount_v1","vsp_p1_panels_mount_v2","vsp_p1_panels_mount_v3","vsp_p1_panels_mount_v4","vsp_p1_panels_mount_v5","vsp_p1_panels_mount_v6"].forEach(id=>{
      const n=document.getElementById(id); if (n) n.remove();
    });
    // remove old error bars by text
    const bad = ["Load gate_summary failed", "body stream already read", "Cannot resolve RID", "payload mismatch", "contract mismatch"];
    Array.from(document.querySelectorAll("div")).forEach(n=>{
      const t=(n.textContent||"");
      if (bad.some(x=>t.includes(x)) && t.length < 320){ try{ n.remove(); }catch(e){} }
    });
  }

  async function render(){
    if (location.pathname !== "/vsp5") return;
    cssOnce();
    cleanup();

    const host = document.getElementById("vsp5_root") || document.querySelector("main") || document.body;
    const mount = el("div",{id:"vsp_p1_panels_mount_v6", class:"vspP1v6Wrap"});
    host.appendChild(mount);

    const rid = await resolveRIDWait(mount);
    if (!rid){
      mount.textContent="";
      mount.appendChild(el("div",{class:"vspP1v6Err"},["Cannot resolve RID after wait."]));
      console.log("[VSP][DashP1V6] RID resolve failed.");
      return;
    }

    let gate=null;
    try{
      gate = unwrapAny(await xhrJSON("/api/vsp/run_file_allow?rid="+encodeURIComponent(rid)+"&path=run_gate_summary.json"));
    }catch(e){
      mount.textContent="";
      mount.appendChild(el("div",{class:"vspP1v6Err"},["Load gate_summary failed (XHR): "+String(e.message||e)]));
      return;
    }

    const fr = await loadFindings(rid);
    if (!fr.ok){
      const info = fr.last || {};
      mount.textContent="";
      mount.appendChild(el("div",{class:"vspP1v6Err"},[
        "Findings not found/contract mismatch. last_path=", String(info.path||"?"),
        " note=", String(info.note||""),
        " keys=", String((info.keys||[]).join(",")),
        info.err ? (" err="+info.err) : ""
      ]));
      console.log("[VSP][DashP1V6] findings probe failed:", fr);
      return;
    }

    const findings = fr.obj;
    const cbs = findings.meta.counts_by_severity;
    const arrFind = findings.findings;

    mount.textContent="";

    const lane = el("div",{class:"vspP1v6Card"},[
      el("h3",{},["Tool Lane (8 tools)"]),
      el("div",{class:"vspP1v6Pills"}, TOOL_ORDER.map(t=>{
        const st = toolObj(gate,t);
        const ns = normStatus(st.status);
        const pill = el("div",{class:"vspP1v6Pill", title:(st.reason||"")},[
          dot(ns),
          el("span",{class:"vspP1v6Mono", style:"font-weight:900;"},[t]),
          el("span",{class:"vspP1v6Muted"},[ns + (st.degraded?" (degraded)":"")]),
        ]);
        pill.addEventListener("click", ()=> { location.href="/runs?rid="+encodeURIComponent(rid); });
        return pill;
      }))
    ]);

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

    const explain = el("div",{class:"vspP1v6Card"},[
      el("h3",{},["Explain why RED / Degraded"]),
      reasons.length
        ? el("ul",{style:"margin:0; padding-left:18px;"}, reasons.slice(0,8).map(r=>el("li",{class:"vspP1v6Muted", style:"margin:6px 0;"},[r])))
        : el("div",{class:"vspP1v6Muted"},["No reasons found in gate summary."])
    ]);

    const topRows = arrFind.map(normFinding).sort((a,b)=>sevRank(a.sev)-sevRank(b.sev)).slice(0,12);

    const tbl = el("div",{class:"vspP1v6Card", style:"flex-basis:100%;"},[
      el("h3",{},["Top Findings (fix-first)"]),
      el("div",{class:"vspP1v6Ok vspP1v6Mono"},[
        "rid=", rid, " • findings=", String(arrFind.length),
        " • CRIT=", String(cbs.CRITICAL||0), " • HIGH=", String(cbs.HIGH||0),
        " • source_path=", fr.path
      ]),
      el("table",{class:"vspP1v6Table", style:"margin-top:10px;"},[
        el("thead",{},[el("tr",{},[
          el("th",{},["Severity"]), el("th",{},["Tool"]), el("th",{},["Title"]), el("th",{},["Location"])
        ])]),
        el("tbody",{}, topRows.map(r=>el("tr",{},[
          el("td",{class:"vspP1v6Mono"},[r.sev||"UNKNOWN"]),
          el("td",{class:"vspP1v6Mono"},[String(r.tool||"")]),
          el("td",{},[String(r.title||"")]),
          el("td",{class:"vspP1v6Mono vspP1v6Muted"},[String(r.loc||"")]),
        ])))
      ])
    ]);

    mount.appendChild(el("div",{class:"vspP1v6Row"},[lane, explain]));
    mount.appendChild(el("div",{class:"vspP1v6Row", style:"margin-top:12px;"},[tbl]));

    console.log("[VSP][DashP1V6] ok rid="+rid+" source_path="+fr.path+" top_findings="+topRows.length);
  }

  // run after load to ensure GateStory already injected DOM text
  window.addEventListener("load", ()=> setTimeout(render, 150));
})();
 /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_V6_XHR_HARD_FIX ===================== */
""").strip("\n")

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

echo "[DONE] Dash P1 V6 XHR hard fix appended."
echo "Next: restart UI then HARD refresh /vsp5 (Ctrl+Shift+R)."
