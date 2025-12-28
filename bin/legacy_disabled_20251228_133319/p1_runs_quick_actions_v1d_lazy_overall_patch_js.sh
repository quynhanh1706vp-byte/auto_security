#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_v1d_${TS}"
echo "[BACKUP] ${JS}.bak_v1d_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

js = Path("static/js/vsp_runs_quick_actions_v1.js")
js.write_text(textwrap.dedent(r"""
/* VSP_P1_RUNS_QUICK_ACTIONS_V1D */
(()=> {
  if (window.__vsp_p1_runs_quick_actions_v1d) return;
  window.__vsp_p1_runs_quick_actions_v1d = true;

  const log = (...a)=>console.log("[RunsQuickV1D]", ...a);
  const warn = (...a)=>console.warn("[RunsQuickV1D]", ...a);

  const API = {
    runs: "/api/vsp/runs",
    exportCsv: "/api/vsp/export_csv",
    exportTgz: "/api/vsp/export_tgz",
    runFile: "/api/vsp/run_file",
    openFolder: "/api/vsp/open_folder", // optional
  };

  const qs=(s,r=document)=>r.querySelector(s);
  const el=(t,attrs={},kids=[])=>{
    const n=document.createElement(t);
    for(const [k,v] of Object.entries(attrs||{})){
      if(k==="class") n.className=v;
      else if(k==="html") n.innerHTML=v;
      else if(k.startsWith("on") && typeof v==="function") n.addEventListener(k.slice(2),v);
      else if(v===null || v===undefined) {}
      else n.setAttribute(k,String(v));
    }
    for(const c of kids||[]) n.appendChild(typeof c==="string"?document.createTextNode(c):c);
    return n;
  };

  function injectStyles(){
    const css = `
      .vsp-runsqa-wrap{padding:12px 0 0 0}
      .vsp-runsqa-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:10px 0 12px 0}
      .vsp-runsqa-toolbar input,.vsp-runsqa-toolbar select{background:#0f172a;color:#e5e7eb;border:1px solid #24314f;border-radius:10px;padding:8px 10px;outline:none}
      .vsp-runsqa-btn{background:#111827;color:#e5e7eb;border:1px solid #24314f;border-radius:10px;padding:7px 10px;cursor:pointer}
      .vsp-runsqa-btn:hover{filter:brightness(1.08)}
      .vsp-runsqa-mini{font-size:12px;opacity:.85}
      .vsp-runsqa-table{width:100%;border-collapse:separate;border-spacing:0 8px}
      .vsp-runsqa-row{background:#0b1220;border:1px solid #1f2a44}
      .vsp-runsqa-row td{padding:10px 10px;border-top:1px solid #1f2a44;border-bottom:1px solid #1f2a44}
      .vsp-runsqa-row td:first-child{border-left:1px solid #1f2a44;border-top-left-radius:12px;border-bottom-left-radius:12px}
      .vsp-runsqa-row td:last-child{border-right:1px solid #1f2a44;border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;border:1px solid #24314f;font-size:12px}
      .vsp-badge.ok{background:#06281b}
      .vsp-badge.amber{background:#2a1c06}
      .vsp-badge.bad{background:#2a0b0b}
      .vsp-badge.dim{opacity:.8}
      .vsp-actions{display:flex;flex-wrap:wrap;gap:6px}
      .vsp-toast{position:fixed;right:16px;bottom:16px;background:#0b1220;border:1px solid #24314f;color:#e5e7eb;padding:10px 12px;border-radius:12px;max-width:560px;box-shadow:0 8px 28px rgba(0,0,0,.35);z-index:99999}
      .vsp-linkbtn{background:transparent;border:0;color:#93c5fd;text-decoration:underline;cursor:pointer;padding:0;margin-left:8px;font-size:12px;opacity:.9}
      .vsp-linkbtn:hover{opacity:1}
    `;
    const st=el("style"); st.textContent=css; document.head.appendChild(st);
  }
  function toast(msg,ms=2400){ const t=el("div",{class:"vsp-toast"},[msg]); document.body.appendChild(t); setTimeout(()=>t.remove(),ms); }

  function pickRid(run){
    return run.run_id || run.rid || run.req_id || run.request_id || run.id || run.RID || run.name || "";
  }

  function deepFindString(obj, re, depth=0){
    if (obj == null || depth > 5) return "";
    if (typeof obj === "string"){
      const m = obj.match(re);
      return m ? m[0] : "";
    }
    if (typeof obj === "number" || typeof obj === "boolean") return "";
    if (Array.isArray(obj)){
      for (const it of obj){
        const v = deepFindString(it, re, depth+1);
        if (v) return v;
      }
      return "";
    }
    if (typeof obj === "object"){
      for (const k of Object.keys(obj)){
        const v = deepFindString(obj[k], re, depth+1);
        if (v) return v;
      }
    }
    return "";
  }

  // ---- lazy cache from run_gate.json ----
  const overallCache = new Map(); // rid -> {overall,degraded,ts}
  const inflight = new Map();     // rid -> Promise
  const MAX_CONC = 4;
  let concNow = 0;
  const queue = [];

  function normOverall(x){
    const s = String(x||"").toUpperCase();
    const m = s.match(/(GREEN|AMBER|RED|PASS|FAIL|OK|ERROR|WARN(ING)?)/);
    return m ? (m[1] === "WARN" ? "AMBER" : m[1]) : (s || "UNKNOWN");
  }

  async function fetchRunGateJson(rid){
    const x = encodeURIComponent(String(rid||""));
    const u = `${API.runFile}?rid=${x}&path=${encodeURIComponent("run_gate.json")}`;
    const r = await fetch(u, {cache:"no-store"});
    if (!r.ok) throw new Error(`run_gate.json HTTP ${r.status}`);
    // may be served as JSON or text
    const ct = (r.headers.get("content-type")||"").toLowerCase();
    if (ct.includes("application/json")) return await r.json();
    const txt = await r.text();
    try { return JSON.parse(txt); } catch(e){ throw new Error("run_gate.json not json"); }
  }

  function extractOverallFromGate(g){
    // common fields
    const direct = g?.overall || g?.overall_status || g?.status || g?.result || "";
    let ov = normOverall(direct);

    // deep scan fallback
    if (ov === "UNKNOWN"){
      const found = deepFindString(g, /(GREEN|AMBER|RED|PASS|FAIL|OK|ERROR|WARN(ING)?)/i);
      ov = normOverall(found);
    }

    // degraded: any by_type.*.degraded true or overall_degraded
    let deg = false;
    try{
      if (g?.by_type && typeof g.by_type === "object"){
        for (const v of Object.values(g.by_type)){
          if (v && typeof v === "object" && v.degraded === true) { deg = true; break; }
        }
      }
      if (g?.degraded === true) deg = true;
      if (g?.any_degraded === true) deg = true;
    }catch(e){}
    return {overall: ov || "UNKNOWN", degraded: !!deg};
  }

  function scheduleResolve(rid, onDone){
    if (!rid) return;
    if (overallCache.has(rid)) { onDone?.(overallCache.get(rid)); return; }
    if (inflight.has(rid)) { inflight.get(rid).then(onDone).catch(()=>{}); return; }

    const job = async ()=>{
      try{
        const g = await fetchRunGateJson(rid);
        const x = extractOverallFromGate(g);
        const rec = { ...x, ts: Date.now() };
        overallCache.set(rid, rec);
        onDone?.(rec);
        return rec;
      }catch(e){
        // keep as unknown
        overallCache.set(rid, {overall:"UNKNOWN", degraded:false, ts: Date.now()});
        onDone?.(overallCache.get(rid));
        throw e;
      }
    };

    const runJob = ()=>{
      concNow++;
      const p = job().finally(()=>{
        concNow--;
        inflight.delete(rid);
        if (queue.length) queue.shift()();
      });
      inflight.set(rid, p);
      return p;
    };

    if (concNow < MAX_CONC) runJob();
    else queue.push(runJob);
  }

  function pickOverall(run){
    const rid = pickRid(run);
    if (rid && overallCache.has(rid)) return overallCache.get(rid).overall;

    const direct = (run.overall || run.overall_status || run.status || run.result || run.verdict || "");
    if (direct) return normOverall(direct);

    const found = deepFindString(run, /(GREEN|AMBER|RED|PASS|FAIL|OK|ERROR|WARN(ING)?)/i);
    return normOverall(found);
  }

  function pickDegraded(run){
    const rid = pickRid(run);
    if (rid && overallCache.has(rid)) return overallCache.get(rid).degraded;

    const keys = ["degraded","any_degraded","tools_degraded","degraded_tools","is_degraded"];
    for (const k of keys){
      if (typeof run[k] === "boolean") return run[k];
    }
    function scan(o, depth=0){
      if (o == null || depth>5) return false;
      if (Array.isArray(o)) return o.some(x=>scan(x, depth+1));
      if (typeof o === "object"){
        for (const [k,v] of Object.entries(o)){
          if (k.toLowerCase().includes("degrad") && v === true) return true;
          if (scan(v, depth+1)) return true;
        }
      }
      return false;
    }
    return scan(run);
  }

  function parseTs(run){
    const raw = run.ts || run.created_at || run.started_at || run.time || run.date || "";
    if (raw){ const d=new Date(raw); if(!isNaN(d.getTime())) return d; }
    const rid=pickRid(run);
    const m=String(rid).match(/(\d{8})_(\d{6})/);
    if(m){
      const y=m[1].slice(0,4), mo=m[1].slice(4,6), da=m[1].slice(6,8);
      const hh=m[2].slice(0,2), mm=m[2].slice(2,4), ss=m[2].slice(4,6);
      const d=new Date(`${y}-${mo}-${da}T${hh}:${mm}:${ss}`); if(!isNaN(d.getTime())) return d;
    }
    return null;
  }
  const pad=n=>String(n).padStart(2,"0");
  function fmtDate(d){ return d?`${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`:""; }

  async function fetchRuns(limit=300){
    const r=await fetch(`${API.runs}?limit=${encodeURIComponent(String(limit))}`,{cache:"no-store"});
    if(!r.ok) throw new Error(`runs http ${r.status}`);
    const data=await r.json();
    if(Array.isArray(data)) return data;
    if(Array.isArray(data.items)) return data.items;
    if(Array.isArray(data.runs)) return data.runs;
    return [];
  }

  function openUrl(u){ window.open(u,"_blank","noopener"); }
  function ridParam(rid){ return encodeURIComponent(String(rid||"")); }
  function urlCsv(rid){ return `${API.exportCsv}?rid=${ridParam(rid)}`; }
  function urlTgz(rid){ return `${API.exportTgz}?rid=${ridParam(rid)}`; }
  function urlRunFile(rid, path){ return `${API.runFile}?rid=${ridParam(rid)}&path=${encodeURIComponent(path)}`; }

  async function tryPing(u){
    try{
      const r = await fetch(u, {method:"GET", cache:"no-store"});
      return r.ok ? "OK" : `HTTP ${r.status}`;
    }catch(e){ return "ERR"; }
  }
  async function go(u, label){
    const st = await tryPing(u);
    if (st !== "OK") toast(`${label}: ${st} (vẫn mở tab để xem)`);
    openUrl(u);
  }
  async function openFolder(rid){
    const u = `${API.openFolder}?rid=${ridParam(rid)}`;
    const st = await tryPing(u);
    if (st !== "OK") return toast(`Open folder: backend chưa hỗ trợ (${st})`);
    toast("Open folder: OK");
  }

  function badgeForOverall(overall){
    const o=String(overall||"UNKNOWN").toUpperCase();
    if (o.includes("GREEN") || o==="OK" || o==="PASS") return el("span",{class:"vsp-badge ok"},[o]);
    if (o.includes("AMBER") || o.includes("WARN")) return el("span",{class:"vsp-badge amber"},[o]);
    if (o.includes("RED") || o.includes("FAIL") || o.includes("ERROR")) return el("span",{class:"vsp-badge bad"},[o]);
    return el("span",{class:"vsp-badge dim"},[o]);
  }

  function mount(){
    injectStyles();
    const anchor = qs("#vspRunsQuickActionsV1") || (()=>{ const d=el("div",{id:"vspRunsQuickActionsV1"}); document.body.insertBefore(d, document.body.firstChild); return d; })();

    const ridIn=el("input",{type:"text",placeholder:"Search RID…",style:"min-width:240px"});
    const overallSel=el("select",{},[
      el("option",{value:""},["Overall: ALL"]),
      el("option",{value:"GREEN"},["GREEN"]),
      el("option",{value:"AMBER"},["AMBER"]),
      el("option",{value:"RED"},["RED"]),
      el("option",{value:"PASS"},["PASS/OK"]),
      el("option",{value:"FAIL"},["FAIL/ERROR"]),
      el("option",{value:"UNKNOWN"},["UNKNOWN"]),
    ]);
    const degrSel=el("select",{},[
      el("option",{value:""},["Degraded: ALL"]),
      el("option",{value:"true"},["Degraded: YES"]),
      el("option",{value:"false"},["Degraded: NO"]),
    ]);
    const fromIn=el("input",{type:"date"});
    const toIn=el("input",{type:"date"});
    const refreshBtn=el("button",{class:"vsp-runsqa-btn"},["Refresh"]);
    const resolveTopBtn=el("button",{class:"vsp-runsqa-btn"},["Resolve top 30"]);
    const clearBtn=el("button",{class:"vsp-runsqa-btn"},["Clear"]);
    const stat=el("span",{class:"vsp-runsqa-mini"},["…"]);

    const wrap=el("div",{class:"vsp-runsqa-wrap"},[
      el("div",{class:"vsp-runsqa-mini"},["Quick Actions V1D: resolve Overall/Degraded từ run_gate.json (lazy + cache, concurrency=4)."]),
      el("div",{class:"vsp-runsqa-toolbar"},[
        ridIn, overallSel, degrSel,
        el("span",{class:"vsp-runsqa-mini"},["From"]), fromIn,
        el("span",{class:"vsp-runsqa-mini"},["To"]), toIn,
        refreshBtn, resolveTopBtn, clearBtn, stat
      ])
    ]);

    const table=el("table",{class:"vsp-runsqa-table"},[
      el("thead",{},[el("tr",{},[
        el("th",{},["RID"]),
        el("th",{},["Date"]),
        el("th",{},["Overall"]),
        el("th",{},["Degraded"]),
        el("th",{},["Actions"]),
      ])]),
      el("tbody",{})
    ]);
    const tbody=table.querySelector("tbody");
    wrap.appendChild(table);
    anchor.appendChild(wrap);

    let runsCache=[];

    function passes(run){
      const rid=pickRid(run);
      const overall=pickOverall(run);
      const degraded=pickDegraded(run);
      const ts=parseTs(run);

      const q=ridIn.value.trim().toLowerCase();
      if(q && !String(rid).toLowerCase().includes(q)) return false;

      const o=overallSel.value.trim().toUpperCase();
      if(o){
        const ov = String(overall||"").toUpperCase();
        if(o==="PASS" && !(ov.includes("PASS")||ov.includes("OK")||ov.includes("GREEN"))) return false;
        else if(o==="FAIL" && !(ov.includes("FAIL")||ov.includes("ERROR")||ov.includes("RED"))) return false;
        else if(o==="GREEN" && !ov.includes("GREEN")) return false;
        else if(o==="AMBER" && !ov.includes("AMBER")) return false;
        else if(o==="RED" && !ov.includes("RED")) return false;
        else if(o==="UNKNOWN" && ov!=="UNKNOWN") return false;
      }

      const dsel=degrSel.value;
      if(dsel==="true" && !degraded) return false;
      if(dsel==="false" && degraded) return false;

      const from=fromIn.value ? new Date(fromIn.value+"T00:00:00") : null;
      const to=toIn.value ? new Date(toIn.value+"T23:59:59") : null;
      if((from||to) && ts){
        if(from && ts<from) return false;
        if(to && ts>to) return false;
      }
      return true;
    }

    function render(){
      const items=runsCache.filter(passes).sort((a,b)=>{
        const ta=parseTs(a), tb=parseTs(b);
        if(ta && tb) return tb.getTime()-ta.getTime();
        if(ta && !tb) return -1;
        if(!ta && tb) return 1;
        return 0;
      });

      tbody.innerHTML="";
      for(const run of items){
        const rid=pickRid(run);
        const overall=pickOverall(run);
        const degraded=pickDegraded(run);
        const ts=parseTs(run);

        const overallCell = el("td",{},[]);
        const badge = badgeForOverall(overall);
        overallCell.appendChild(badge);

        if (String(overall).toUpperCase()==="UNKNOWN" && rid){
          const btn = el("button",{class:"vsp-linkbtn", onclick: ()=>{
            scheduleResolve(rid, ()=>render()); // resolve then rerender
            toast("Resolving overall…");
          }},["resolve"]);
          overallCell.appendChild(btn);
        }

        const ridCell = el("td",{},[
          el("div",{},[String(rid||"(no rid)")]),
          el("div",{class:"vsp-runsqa-mini"},[
            el("button",{class:"vsp-runsqa-btn", onclick: async ()=>{
              try{ await navigator.clipboard.writeText(String(rid||"")); toast("Copied RID"); } catch(e){ toast("Copy failed"); }
            }},["Copy RID"]),
            " ",
            el("button",{class:"vsp-runsqa-btn", onclick: async ()=>openFolder(String(rid||""))},["Open folder"]),
          ])
        ]);

        const actions = el("div",{class:"vsp-actions"},[
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>go(urlCsv(rid),"CSV")},["CSV"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>go(urlTgz(rid),"TGZ")},["TGZ"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>go(urlRunFile(rid,"run_gate.json"),"Open JSON")},["Open JSON"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>go(urlRunFile(rid,"reports/findings_unified.html"),"Open HTML")},["Open HTML"]),
        ]);

        const tr = el("tr",{class:"vsp-runsqa-row"},[
          ridCell,
          el("td",{},[fmtDate(ts)||"-"]),
          overallCell,
          el("td",{},[degraded ? el("span",{class:"vsp-badge amber"},["DEGRADED"]) : el("span",{class:"vsp-badge ok"},["OK"])]),
          el("td",{},[actions]),
        ]);
        tbody.appendChild(tr);
      }
      stat.textContent = `Runs: ${items.length}/${runsCache.length} | cache=${overallCache.size}`;
    }

    async function load(){
      stat.textContent="Loading…";
      try{
        runsCache = await fetchRuns(900);
        render();
        log("loaded + running, runs=", runsCache.length);
      }catch(e){
        warn("load failed:", e);
        stat.textContent="Load failed (see console)";
        toast("Load runs failed — check /api/vsp/runs");
      }
    }

    function resolveTopN(n=30){
      const items = runsCache.slice(0, n);
      for (const run of items){
        const rid = pickRid(run);
        if (!rid) continue;
        if (pickOverall(run) !== "UNKNOWN") continue;
        scheduleResolve(rid, ()=>render());
      }
      toast(`Resolving top ${n}…`);
    }

    [ridIn,overallSel,degrSel,fromIn,toIn].forEach(x=>x.addEventListener("input", render));
    refreshBtn.addEventListener("click", load);
    resolveTopBtn.addEventListener("click", ()=>resolveTopN(30));
    clearBtn.addEventListener("click", ()=>{ ridIn.value=""; overallSel.value=""; degrSel.value=""; fromIn.value=""; toIn.value=""; render(); });

    load();
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
""").lstrip(), encoding="utf-8")

print("[OK] wrote V1D =>", js)
PY

echo "[DONE] Patched JS to V1D. Mở /runs và Ctrl+Shift+R. Bấm 'Resolve top 30' để overall hiện GREEN/AMBER/RED."
