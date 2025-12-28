#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_v1b_${TS}"
echo "[BACKUP] ${JS}.bak_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

js = Path("static/js/vsp_runs_quick_actions_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

# Replace whole file with v1b (safe, deterministic)
js.write_text(textwrap.dedent(r"""
/* VSP_P1_RUNS_QUICK_ACTIONS_V1B */
(()=> {
  if (window.__vsp_p1_runs_quick_actions_v1) return;
  window.__vsp_p1_runs_quick_actions_v1 = true;

  const log = (...a)=>console.log("[RunsQuickV1B]", ...a);
  const warn = (...a)=>console.warn("[RunsQuickV1B]", ...a);

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
      .vsp-runsqa-btn[disabled]{opacity:.45;cursor:not-allowed}
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
      .vsp-toast{position:fixed;right:16px;bottom:16px;background:#0b1220;border:1px solid #24314f;color:#e5e7eb;padding:10px 12px;border-radius:12px;max-width:420px;box-shadow:0 8px 28px rgba(0,0,0,.35);z-index:99999}
    `;
    const st=el("style"); st.textContent=css; document.head.appendChild(st);
  }
  function toast(msg,ms=2200){ const t=el("div",{class:"vsp-toast"},[msg]); document.body.appendChild(t); setTimeout(()=>t.remove(),ms); }

  function pickRid(run){ return run.run_id || run.rid || run.req_id || run.id || ""; }
  function pickOverall(run){ return String(run.overall || run.overall_status || run.status || "").toUpperCase(); }
  function pickDegraded(run){
    if (typeof run.degraded === "boolean") return run.degraded;
    if (typeof run.any_degraded === "boolean") return run.any_degraded;
    if (typeof run.tools_degraded === "boolean") return run.tools_degraded;
    if (typeof run.degraded_tools_count === "number") return run.degraded_tools_count > 0;
    if (typeof run.tools_degraded_count === "number") return run.tools_degraded_count > 0;
    return false;
  }
  function parseTs(run){
    const raw = run.ts || run.created_at || run.started_at || run.time || run.date || "";
    if (raw){ const d=new Date(raw); if(!isNaN(d.getTime())) return d; }
    const rid=pickRid(run);
    const m=rid.match(/(\d{8})_(\d{6})/);
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

  async function openBest(cands){
    // best-effort: try fetch ok then open. If fails, still open first.
    for(const u of cands){
      try{
        const rr=await fetch(u,{cache:"no-store"});
        if(rr.ok){ window.open(u,"_blank","noopener"); return; }
      }catch(e){}
    }
    window.open(cands[0],"_blank","noopener");
  }

  async function downloadCsv(rid){
    const x=encodeURIComponent(rid);
    await openBest([`${API.exportCsv}?rid=${x}`,`${API.exportCsv}?run_id=${x}`,`${API.exportCsv}?req_id=${x}`]);
  }
  async function downloadTgz(rid){
    const x=encodeURIComponent(rid);
    await openBest([`${API.exportTgz}?rid=${x}`,`${API.exportTgz}?run_id=${x}`,`${API.exportTgz}?req_id=${x}`]);
  }
  async function openRunFile(rid, path){
    const x=encodeURIComponent(rid), p=encodeURIComponent(path);
    await openBest([
      `${API.runFile}?rid=${x}&path=${p}`,
      `${API.runFile}?run_id=${x}&path=${p}`,
      `${API.runFile}?req_id=${x}&path=${p}`,
      `${API.runFile}?rid=${x}&file=${p}`,
      `${API.runFile}?run_id=${x}&file=${p}`,
    ]);
  }
  async function openFolder(rid){
    const x=encodeURIComponent(rid);
    try{
      const r=await fetch(`${API.openFolder}?rid=${x}`,{cache:"no-store"});
      if(!r.ok) return toast("open folder: backend chưa hỗ trợ");
      toast("open folder: OK");
    }catch(e){ toast("open folder: backend chưa hỗ trợ"); }
  }

  function badgeForOverall(overall){
    const o=(overall||"").toUpperCase();
    if (o.includes("GREEN") || o==="OK" || o==="PASS") return el("span",{class:"vsp-badge ok"},[o||"OK"]);
    if (o.includes("AMBER") || o.includes("WARN")) return el("span",{class:"vsp-badge amber"},[o||"AMBER"]);
    if (o.includes("RED") || o.includes("FAIL") || o.includes("ERROR")) return el("span",{class:"vsp-badge bad"},[o||"FAIL"]);
    return el("span",{class:"vsp-badge dim"},[o||"UNKNOWN"]);
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
    ]);
    const degrSel=el("select",{},[
      el("option",{value:""},["Degraded: ALL"]),
      el("option",{value:"true"},["Degraded: YES"]),
      el("option",{value:"false"},["Degraded: NO"]),
    ]);
    const fromIn=el("input",{type:"date"});
    const toIn=el("input",{type:"date"});
    const refreshBtn=el("button",{class:"vsp-runsqa-btn"},["Refresh"]);
    const clearBtn=el("button",{class:"vsp-runsqa-btn"},["Clear"]);
    const stat=el("span",{class:"vsp-runsqa-mini"},["…"]);

    const wrap=el("div",{class:"vsp-runsqa-wrap"},[
      el("div",{class:"vsp-runsqa-mini"},["Quick Actions V1B: nút chỉ bật khi file/export có sẵn (dựa theo items[].has)."]),
      el("div",{class:"vsp-runsqa-toolbar"},[
        ridIn, overallSel, degrSel,
        el("span",{class:"vsp-runsqa-mini"},["From"]), fromIn,
        el("span",{class:"vsp-runsqa-mini"},["To"]), toIn,
        refreshBtn, clearBtn, stat
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
        if(o==="PASS" && !(overall.includes("PASS")||overall.includes("OK")||overall.includes("GREEN"))) return false;
        else if(o==="FAIL" && !(overall.includes("FAIL")||overall.includes("ERROR")||overall.includes("RED"))) return false;
        else if(o==="GREEN" && !overall.includes("GREEN")) return false;
        else if(o==="AMBER" && !overall.includes("AMBER")) return false;
        else if(o==="RED" && !overall.includes("RED")) return false;
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

    function btn(label, enabled, onClick){
      return el("button", {class:"vsp-runsqa-btn", disabled: enabled?null:"", onclick: enabled?onClick:()=>toast(`${label}: not available`)}, [label]);
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
        const has=(run.has && typeof run.has==="object") ? run.has : {};

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
          btn("CSV",  !!has.csv,  ()=>downloadCsv(String(rid||""))),
          btn("TGZ",  true,      ()=>downloadTgz(String(rid||""))),
          btn("Open JSON", !!has.json, ()=>openRunFile(String(rid||""), "run_gate.json")),
          btn("Open HTML", !!has.html, ()=>openRunFile(String(rid||""), "reports/findings_unified.html")),
        ]);

        const tr = el("tr",{class:"vsp-runsqa-row"},[
          ridCell,
          el("td",{},[fmtDate(ts)||"-"]),
          el("td",{},[badgeForOverall(overall)]),
          el("td",{},[degraded ? el("span",{class:"vsp-badge amber"},["DEGRADED"]) : el("span",{class:"vsp-badge ok"},["OK"])]),
          el("td",{},[actions]),
        ]);
        tbody.appendChild(tr);
      }
      stat.textContent = `Runs: ${items.length}/${runsCache.length}`;
    }

    async function load(){
      stat.textContent="Loading…";
      try{
        runsCache = await fetchRuns(500);
        render();
        log("loaded + running, runs=", runsCache.length);
      }catch(e){
        warn("load failed:", e);
        stat.textContent="Load failed (see console)";
        toast("Load runs failed — check /api/vsp/runs");
      }
    }

    [ridIn,overallSel,degrSel,fromIn,toIn].forEach(x=>x.addEventListener("input", render));
    refreshBtn.addEventListener("click", load);
    clearBtn.addEventListener("click", ()=>{ ridIn.value=""; overallSel.value=""; degrSel.value=""; fromIn.value=""; toIn.value=""; render(); });

    load();
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
""").lstrip(), encoding="utf-8")

print("[OK] wrote V1B =>", js)
PY

echo "[DONE] JS patched to V1B. Không cần restart. Mở /runs và hard refresh (Ctrl+Shift+R)."
