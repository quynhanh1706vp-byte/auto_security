#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_v1h_${TS}"
echo "[BACKUP] ${JS}.bak_v1h_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

Path("static/js/vsp_runs_quick_actions_v1.js").write_text(textwrap.dedent(r"""
/* VSP_P1_RUNS_QUICK_ACTIONS_V1H (KPI + Pagination; NO auto probe run_file => no 404 spam) */
(()=> {
  if (window.__vsp_p1_runs_quick_actions_v1h) return;
  window.__vsp_p1_runs_quick_actions_v1h = true;

  const log = (...a)=>console.log("[RunsQuickV1H]", ...a);

  const API = {
    runs: "/api/vsp/runs",
    exportCsv: "/api/vsp/export_csv",
    exportTgz: "/api/vsp/export_tgz",
    runFile: "/api/vsp/run_file",       // might not exist; we DO NOT auto-probe
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
      .vsp-runsqa-btn[disabled]{opacity:.45;cursor:not-allowed}
      .vsp-runsqa-mini{font-size:12px;opacity:.85}
      .vsp-runsqa-table{width:100%;border-collapse:separate;border-spacing:0 8px}
      .vsp-runsqa-row{background:#0b1220;border:1px solid #1f2a44}
      .vsp-runsqa-row td{padding:10px 10px;border-top:1px solid #1f2a44;border-bottom:1px solid #1f2a44;vertical-align:middle}
      .vsp-runsqa-row td:first-child{border-left:1px solid #1f2a44;border-top-left-radius:12px;border-bottom-left-radius:12px}
      .vsp-runsqa-row td:last-child{border-right:1px solid #1f2a44;border-top-right-radius:12px;border-bottom-right-radius:12px}
      .vsp-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;border:1px solid #24314f;font-size:12px;white-space:nowrap}
      .vsp-badge.ok{background:#06281b}
      .vsp-badge.amber{background:#2a1c06}
      .vsp-badge.bad{background:#2a0b0b}
      .vsp-badge.dim{opacity:.85}
      .vsp-actions{display:flex;flex-wrap:wrap;gap:6px}
      .vsp-toast{position:fixed;right:16px;bottom:16px;background:#0b1220;border:1px solid #24314f;color:#e5e7eb;padding:10px 12px;border-radius:12px;max-width:560px;box-shadow:0 8px 28px rgba(0,0,0,.35);z-index:99999}
      .vsp-linkbtn{background:transparent;border:0;color:#93c5fd;text-decoration:underline;cursor:pointer;padding:0;margin-left:8px;font-size:12px;opacity:.9}
      .vsp-linkbtn:hover{opacity:1}
      .vsp-legacy-hidden{display:none !important}

      .vsp-kpis{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:6px 0 10px 0}
      .vsp-kpi{display:flex;gap:8px;align-items:center;border:1px solid #24314f;border-radius:14px;background:#0b1220;padding:8px 10px}
      .vsp-kpi .k{font-size:12px;opacity:.85}
      .vsp-kpi .v{font-size:14px;font-weight:700}
      .vsp-pager{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:6px 0 10px 0}
      .vsp-pager input{width:84px}
      .vsp-cap{opacity:.85}
    `;
    const st=el("style"); st.textContent=css; document.head.appendChild(st);
  }
  function toast(msg,ms=2200){ const t=el("div",{class:"vsp-toast"},[msg]); document.body.appendChild(t); setTimeout(()=>t.remove(),ms); }

  function pickRid(run){
    return run.run_id || run.rid || run.req_id || run.request_id || run.id || run.RID || run.name || "";
  }
  function deepFindString(obj, re, depth=0){
    if (obj == null || depth > 5) return "";
    if (typeof obj === "string"){ const m=obj.match(re); return m?m[0]:""; }
    if (typeof obj === "number" || typeof obj === "boolean") return "";
    if (Array.isArray(obj)){ for (const it of obj){ const v=deepFindString(it,re,depth+1); if(v) return v; } return ""; }
    if (typeof obj === "object"){ for (const k of Object.keys(obj)){ const v=deepFindString(obj[k],re,depth+1); if(v) return v; } }
    return "";
  }
  function normOverall(x){
    const s = String(x||"").toUpperCase();
    const m = s.match(/(GREEN|AMBER|RED|PASS|FAIL|OK|ERROR|WARN(ING)?)/);
    if (!m) return s || "UNKNOWN";
    const t=m[1];
    if (t==="WARN") return "AMBER";
    if (t==="OK") return "GREEN";
    if (t==="ERROR") return "RED";
    return t;
  }
  function pickOverall(run){
    const direct = (run.overall || run.overall_status || run.status || run.result || run.verdict || "");
    if (direct) return normOverall(direct);
    const found = deepFindString(run, /(GREEN|AMBER|RED|PASS|FAIL|OK|ERROR|WARN(ING)?)/i);
    return normOverall(found);
  }
  function pickDegraded(run){
    const keys = ["degraded","any_degraded","tools_degraded","degraded_tools","is_degraded"];
    for (const k of keys){
      if (typeof run[k] === "boolean") return run[k];
    }
    return false;
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
  async function tryPing(u){
    try{
      const r = await fetch(u, {method:"GET", cache:"no-store"});
      return r.ok ? "OK" : `HTTP ${r.status}`;
    }catch(e){ return "ERR"; }
  }
  function openUrl(u){ window.open(u,"_blank","noopener"); }
  function ridParam(rid){ return encodeURIComponent(String(rid||"")); }
  function urlCsv(rid){ return `${API.exportCsv}?rid=${ridParam(rid)}`; }
  function urlTgz(rid){ return `${API.exportTgz}?rid=${ridParam(rid)}`; }

  // legacy hide
  function hideLegacyExcept(anchor){
    const hidden = [];
    const rx = /(VSP\s*Runs\s*&\s*Reports|Runs\s*&\s*Reports)/i;
    function hideNode(n){
      if (!n || n===document.body) return;
      if (anchor && anchor.contains(n)) return;
      if (n.getAttribute("data-vsp-legacy-hidden")==="1") return;
      n.classList.add("vsp-legacy-hidden");
      n.setAttribute("data-vsp-legacy-hidden","1");
      hidden.push(n);
    }
    const nodes = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,section,main"))
      .filter(n => n && n.textContent && rx.test(n.textContent.trim()))
      .slice(0, 8);
    for (const h of nodes){
      let cur=h;
      for (let i=0;i<10;i++){
        if (!cur || cur===document.body) break;
        if (cur.querySelector && cur.querySelector("table")) { hideNode(cur); break; }
        cur=cur.parentElement;
      }
    }
    window.__vsp_runs_legacy_hidden_nodes = hidden;
    return hidden;
  }
  function toggleLegacy(show){
    const nodes = window.__vsp_runs_legacy_hidden_nodes || [];
    for (const n of nodes){
      if (!n) continue;
      if (show) n.classList.remove("vsp-legacy-hidden");
      else n.classList.add("vsp-legacy-hidden");
    }
  }

  function badgeForOverall(overall){
    const o=String(overall||"UNKNOWN").toUpperCase();
    if (o.includes("GREEN") || o==="OK" || o==="PASS") return el("span",{class:"vsp-badge ok"},[o==="OK"?"GREEN":o]);
    if (o.includes("AMBER") || o.includes("WARN")) return el("span",{class:"vsp-badge amber"},[o.includes("WARN")?"AMBER":o]);
    if (o.includes("RED") || o.includes("FAIL") || o.includes("ERROR")) return el("span",{class:"vsp-badge bad"},[o.includes("ERROR")?"RED":o]);
    return el("span",{class:"vsp-badge dim"},[o||"UNKNOWN"]);
  }

  function mount(){
    injectStyles();
    const anchor = qs("#vspRunsQuickActionsV1") || (()=>{ const d=el("div",{id:"vspRunsQuickActionsV1"}); document.body.insertBefore(d, document.body.firstChild); return d; })();
    hideLegacyExcept(anchor);

    let legacyShown=false;

    const ridIn=el("input",{type:"text",placeholder:"Search RID…",style:"min-width:240px"});
    const overallSel=el("select",{},[
      el("option",{value:""},["Overall: ALL"]),
      el("option",{value:"GREEN"},["GREEN"]),
      el("option",{value:"AMBER"},["AMBER"]),
      el("option",{value:"RED"},["RED"]),
      el("option",{value:"UNKNOWN"},["UNKNOWN"]),
    ]);
    const degrSel=el("select",{},[
      el("option",{value:""},["Degraded: ALL"]),
      el("option",{value:"true"},["Degraded: YES"]),
      el("option",{value:"false"},["Degraded: NO"]),
    ]);
    const fromIn=el("input",{type:"date"});
    const toIn=el("input",{type:"date"});

    const pageSizeSel=el("select",{},[
      el("option",{value:"10"},["10/page"]),
      el("option",{value:"20", selected:"selected"},["20/page"]),
      el("option",{value:"50"},["50/page"]),
      el("option",{value:"100"},["100/page"]),
    ]);
    const prevBtn=el("button",{class:"vsp-runsqa-btn"},["Prev"]);
    const nextBtn=el("button",{class:"vsp-runsqa-btn"},["Next"]);
    const pageIn=el("input",{type:"number", min:"1", value:"1"});
    const pageInfo=el("span",{class:"vsp-runsqa-mini"},["1/1"]);

    const refreshBtn=el("button",{class:"vsp-runsqa-btn"},["Refresh"]);
    const legacyBtn=el("button",{class:"vsp-runsqa-btn"},["Show legacy"]);
    const clearBtn=el("button",{class:"vsp-runsqa-btn"},["Clear"]);
    const stat=el("span",{class:"vsp-runsqa-mini"},["…"]);
    const cap=el("span",{class:"vsp-cap vsp-runsqa-mini"},["run_file: OFF (no auto probe)"]);

    const checkBtn=el("button",{class:"vsp-runsqa-btn"},["Check run_file"]);
    checkBtn.addEventListener("click", async ()=>{
      // This is optional manual check. It may 404 depending on backend.
      // We keep it manual so demo stays clean.
      const rid0 = (window.__vsp_runs_latest_rid||"");
      if (!rid0) return toast("No RID to probe");
      const u = `${API.runFile}?rid=${ridParam(rid0)}&path=${encodeURIComponent("run_manifest.json")}`;
      const st = await tryPing(u);
      cap.textContent = (st==="OK") ? "run_file: YES (path param)" : `run_file: NO (${st})`;
      toast(cap.textContent);
    });

    legacyBtn.addEventListener("click", ()=>{
      legacyShown=!legacyShown;
      toggleLegacy(legacyShown);
      legacyBtn.textContent = legacyShown ? "Hide legacy" : "Show legacy";
    });

    // KPI
    const mkK = (name)=>({name, v: el("span",{class:"v"},["0"])});
    const kTotal=mkK("Total"), kG=mkK("GREEN"), kA=mkK("AMBER"), kR=mkK("RED"), kU=mkK("UNKNOWN"), kD=mkK("DEGRADED");
    const kpis = el("div",{class:"vsp-kpis"},[
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kTotal.name]), kTotal.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kG.name]), kG.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kA.name]), kA.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kR.name]), kR.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kU.name]), kU.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},[kD.name]), kD.v]),
      el("div",{class:"vsp-kpi"},[el("span",{class:"k"},["Capabilities"]), cap]),
    ]);

    const pager = el("div",{class:"vsp-pager"},[
      el("span",{class:"vsp-runsqa-mini"},["Page size"]), pageSizeSel,
      prevBtn, nextBtn,
      el("span",{class:"vsp-runsqa-mini"},["Page"]), pageIn,
      pageInfo,
    ]);

    const wrap=el("div",{class:"vsp-runsqa-wrap"},[
      el("div",{class:"vsp-runsqa-mini"},["Runs & Reports Quick Actions V1H: KPI + pagination. Không auto-probe run_file => không có 404 spam. (Nếu muốn kiểm tra run_file thì bấm Check run_file)."]),
      kpis,
      el("div",{class:"vsp-runsqa-toolbar"},[
        ridIn, overallSel, degrSel,
        el("span",{class:"vsp-runsqa-mini"},["From"]), fromIn,
        el("span",{class:"vsp-runsqa-mini"},["To"]), toIn,
        refreshBtn, checkBtn, legacyBtn, clearBtn, stat
      ]),
      pager
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
    let page=1;

    function recomputeKpi(allItems){
      let g=0,a=0,r=0,u=0,d=0;
      for (const run of allItems){
        const ov = String(pickOverall(run)||"UNKNOWN").toUpperCase();
        if (ov.includes("GREEN") || ov==="OK" || ov==="PASS") g++;
        else if (ov.includes("AMBER") || ov.includes("WARN")) a++;
        else if (ov.includes("RED") || ov.includes("FAIL") || ov.includes("ERROR")) r++;
        else u++;
        if (pickDegraded(run)) d++;
      }
      kTotal.v.textContent = String(allItems.length);
      kG.v.textContent = String(g);
      kA.v.textContent = String(a);
      kR.v.textContent = String(r);
      kU.v.textContent = String(u);
      kD.v.textContent = String(d);
    }

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
        if(o==="GREEN" && !ov.includes("GREEN")) return false;
        if(o==="AMBER" && !ov.includes("AMBER")) return false;
        if(o==="RED" && !ov.includes("RED")) return false;
        if(o==="UNKNOWN" && ov!=="UNKNOWN") return false;
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

    function getFilteredSorted(){
      return runsCache
        .filter(passes)
        .sort((a,b)=>{
          const ta=parseTs(a), tb=parseTs(b);
          if(ta && tb) return tb.getTime()-ta.getTime();
          if(ta && !tb) return -1;
          if(!ta && tb) return 1;
          return 0;
        });
    }

    function clampPage(p, totalPages){
      if (p < 1) return 1;
      if (p > totalPages) return totalPages;
      return p;
    }

    function render(){
      const itemsAll = getFilteredSorted();
      recomputeKpi(itemsAll);

      const pageSize = parseInt(pageSizeSel.value || "20", 10);
      const totalPages = Math.max(1, Math.ceil(itemsAll.length / pageSize));
      page = clampPage(page, totalPages);
      pageIn.value = String(page);
      pageInfo.textContent = `${page}/${totalPages}`;

      const start = (page-1)*pageSize;
      const items = itemsAll.slice(start, start + pageSize);

      tbody.innerHTML="";
      for(const run of items){
        const rid=pickRid(run);
        const overall=pickOverall(run);
        const degraded=pickDegraded(run);
        const ts=parseTs(run);

        const actions = el("div",{class:"vsp-actions"},[
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>openUrl(urlCsv(rid))},["CSV"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>openUrl(urlTgz(rid))},["TGZ"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>toast("Open JSON/HTML cần backend hỗ trợ /api/vsp/run_file")},["Open JSON"]),
          el("button",{class:"vsp-runsqa-btn", onclick: async ()=>toast("Open JSON/HTML cần backend hỗ trợ /api/vsp/run_file")},["Open HTML"]),
        ]);

        const tr = el("tr",{class:"vsp-runsqa-row"},[
          el("td",{},[
            el("div",{},[String(rid||"(no rid)")]),
            el("div",{class:"vsp-runsqa-mini"},[
              el("button",{class:"vsp-runsqa-btn", onclick: async ()=>{
                try{ await navigator.clipboard.writeText(String(rid||"")); toast("Copied RID"); } catch(e){ toast("Copy failed"); }
              }},["Copy RID"]),
              " ",
              el("button",{class:"vsp-runsqa-btn", onclick: async ()=>{
                const u = `${API.openFolder}?rid=${ridParam(rid)}`;
                const st = await tryPing(u);
                if (st !== "OK") return toast(`Open folder: backend chưa hỗ trợ (${st})`);
                toast("Open folder: OK");
              }},["Open folder"]),
            ])
          ]),
          el("td",{},[fmtDate(ts)||"-"]),
          el("td",{},[badgeForOverall(overall)]),
          el("td",{},[degraded ? el("span",{class:"vsp-badge amber"},["DEGRADED"]) : el("span",{class:"vsp-badge ok"},["OK"])]),
          el("td",{},[actions]),
        ]);
        tbody.appendChild(tr);
      }

      stat.textContent = `Showing ${items.length}/${itemsAll.length} (runs=${runsCache.length})`;
      prevBtn.disabled = (page<=1);
      nextBtn.disabled = (page>=totalPages);
    }

    prevBtn.addEventListener("click", ()=>{ page=Math.max(1,page-1); render(); });
    nextBtn.addEventListener("click", ()=>{ page=page+1; render(); });
    pageIn.addEventListener("change", ()=>{
      const v=parseInt(pageIn.value||"1",10);
      page=isNaN(v)?1:v;
      render();
    });
    pageSizeSel.addEventListener("change", ()=>{ page=1; render(); });

    async function load(){
      stat.textContent="Loading…";
      runsCache = await fetchRuns(1200);
      page=1;
      window.__vsp_runs_latest_rid = pickRid((runsCache && runsCache[0]) || {});
      render();
      log("loaded + running, runs=", runsCache.length);
    }

    [ridIn,overallSel,degrSel,fromIn,toIn].forEach(x=>x.addEventListener("input", ()=>{ page=1; render(); }));
    refreshBtn.addEventListener("click", load);
    clearBtn.addEventListener("click", ()=>{ ridIn.value=""; overallSel.value=""; degrSel.value=""; fromIn.value=""; toIn.value=""; page=1; render(); });

    load();
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
""").lstrip(), encoding="utf-8")
print("[OK] wrote V1H => static/js/vsp_runs_quick_actions_v1.js")
PY

echo "[DONE] V1H installed. Open /runs and Ctrl+Shift+R. Sẽ không còn 404 spam nữa."
