#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_topux_${TS}"
echo "[BACKUP] ${JS}.bak_topux_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_TOPFINDINGS_UX_FILTER_MODAL_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_TOPFINDINGS_UX_FILTER_MODAL_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const css = `
#vsp_topux_bar_v1{
  display:flex; gap:8px; align-items:center; flex-wrap:wrap;
  margin: 6px 0 8px 0;
}
#vsp_topux_bar_v1 select, #vsp_topux_bar_v1 input{
  border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.05);
  color:rgba(255,255,255,.92);
  padding:7px 10px;
  border-radius:12px;
  outline:none;
  font-weight:800;
}
#vsp_topux_bar_v1 input{min-width:260px}
#vsp_topux_bar_v1 .muted{opacity:.72; font-weight:800}
#vsp_topux_modal_v1{
  position:fixed; inset:0; z-index:130000;
  background:rgba(0,0,0,.55); display:none; align-items:center; justify-content:center;
}
#vsp_topux_modal_v1 .card{
  width:min(980px, 94vw); max-height:84vh; overflow:auto;
  border-radius:16px;
  background:rgba(10,16,32,.96);
  border:1px solid rgba(255,255,255,.12);
  box-shadow:0 18px 55px rgba(0,0,0,.55);
  padding:14px;
  color:rgba(255,255,255,.92);
  font:12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
}
#vsp_topux_modal_v1 .top{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}
#vsp_topux_modal_v1 .ttl{font-weight:900;letter-spacing:.2px}
#vsp_topux_modal_v1 button{
  cursor:pointer;border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.06); color:rgba(255,255,255,.92);
  padding:7px 10px;border-radius:12px;font-weight:900;
}
#vsp_topux_modal_v1 pre{
  white-space:pre-wrap; word-break:break-word;
  background:rgba(255,255,255,.04);
  border:1px solid rgba(255,255,255,.10);
  padding:10px; border-radius:14px;
}
    `.trim();

    const ensureStyle=()=>{
      if (document.getElementById("vsp_topux_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_topux_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const ensureModal=()=>{
      ensureStyle();
      if (document.getElementById("vsp_topux_modal_v1")) return;
      const m=document.createElement("div");
      m.id="vsp_topux_modal_v1";
      m.innerHTML = `
        <div class="card">
          <div class="top">
            <div class="ttl" id="vsp_topux_ttl_v1">Finding detail</div>
            <div style="display:flex;gap:8px;align-items:center">
              <button id="vsp_topux_copy_v1">Copy</button>
              <button id="vsp_topux_close_v1">Close</button>
            </div>
          </div>
          <div class="muted" id="vsp_topux_meta_v1" style="margin-bottom:10px"></div>
          <pre id="vsp_topux_pre_v1">{}</pre>
        </div>
      `;
      document.body.appendChild(m);
      m.addEventListener("click",(e)=>{ if(e.target===m) m.style.display="none"; });
      document.getElementById("vsp_topux_close_v1").addEventListener("click",()=>{ m.style.display="none"; });
      document.getElementById("vsp_topux_copy_v1").addEventListener("click",async()=>{
        try{
          const t=(document.getElementById("vsp_topux_pre_v1")||{}).textContent||"";
          await navigator.clipboard.writeText(t);
        }catch(e){}
      });
    };

    const showModal=(obj)=>{
      ensureModal();
      const m=document.getElementById("vsp_topux_modal_v1");
      const pre=document.getElementById("vsp_topux_pre_v1");
      const meta=document.getElementById("vsp_topux_meta_v1");
      if (pre) pre.textContent = JSON.stringify(obj||{}, null, 2);
      const sev=(obj && (obj.severity||obj.sev||obj.level))||"";
      const tool=(obj && (obj.tool||obj.source||obj.engine))||"";
      const loc=(obj && (obj.location||obj.path||obj.file))||"";
      if (meta) meta.textContent = `${sev} • ${tool} • ${loc}`.trim();
      if (m) m.style.display="flex";
    };

    // Find the "Top findings (sample)" table, then enhance it.
    const findTopTable = ()=>{
      // heuristic: the sample table has headers Severity/Tool/Title/Location
      const tables=[...document.querySelectorAll("table")];
      for (const t of tables){
        const th=[...t.querySelectorAll("th")].map(x=>(x.textContent||"").trim().toLowerCase());
        if (th.includes("severity") && th.includes("tool") && th.includes("title") && th.includes("location")) return t;
      }
      return null;
    };

    const normalize=(v)=>String(v||"").toLowerCase();

    const parseRow = (tr)=>{
      const tds=[...tr.querySelectorAll("td")];
      if (tds.length<4) return null;
      const sev=(tds[0].textContent||"").trim();
      const tool=(tds[1].textContent||"").trim();
      const title=(tds[2].textContent||"").trim();
      const loc=(tds[3].textContent||"").trim();
      return {severity:sev, tool:tool, title:title, location:loc};
    };

    const state = {
      tool:"ALL",
      sev:"ALL",
      q:"",
      rows:[], // {tr,obj}
    };

    const applyFilter=()=>{
      const q=normalize(state.q);
      for (const r of state.rows){
        const o=r.obj||{};
        const okTool = (state.tool==="ALL") || normalize(o.tool)===normalize(state.tool);
        const okSev  = (state.sev==="ALL")  || normalize(o.severity)===normalize(state.sev);
        const okQ = (!q) || (normalize(o.title).includes(q) || normalize(o.location).includes(q) || normalize(o.tool).includes(q));
        r.tr.style.display = (okTool && okSev && okQ) ? "" : "none";
      }
      const cnt = state.rows.filter(r=>r.tr.style.display!=="none").length;
      const hint=document.getElementById("vsp_topux_hint_v1");
      if (hint) hint.textContent = `${cnt}/${state.rows.length}`;
    };

    const buildBar=(table)=>{
      if (document.getElementById("vsp_topux_bar_v1")) return;
      const wrap = table.parentElement || table;
      const bar=document.createElement("div");
      bar.id="vsp_topux_bar_v1";
      bar.innerHTML = `
        <span class="muted">Filter:</span>
        <select id="vsp_topux_sev_v1"><option value="ALL">Severity: ALL</option></select>
        <select id="vsp_topux_tool_v1"><option value="ALL">Tool: ALL</option></select>
        <input id="vsp_topux_q_v1" placeholder="Search title/location/tool… (live)" />
        <span class="muted">show</span> <span class="muted" id="vsp_topux_hint_v1">0/0</span>
      `;
      wrap.insertBefore(bar, table);

      const sevSel=document.getElementById("vsp_topux_sev_v1");
      const toolSel=document.getElementById("vsp_topux_tool_v1");
      const q=document.getElementById("vsp_topux_q_v1");

      sevSel.addEventListener("change",()=>{ state.sev=sevSel.value; applyFilter(); });
      toolSel.addEventListener("change",()=>{ state.tool=toolSel.value; applyFilter(); });
      q.addEventListener("input",()=>{ state.q=q.value||""; applyFilter(); });
    };

    const refreshOptions=()=>{
      const sevSel=document.getElementById("vsp_topux_sev_v1");
      const toolSel=document.getElementById("vsp_topux_tool_v1");
      if (!sevSel || !toolSel) return;

      const sevs=[...new Set(state.rows.map(r=>(r.obj.severity||"").trim()).filter(Boolean))].sort();
      const tools=[...new Set(state.rows.map(r=>(r.obj.tool||"").trim()).filter(Boolean))].sort();

      const curSev=state.sev, curTool=state.tool;

      sevSel.innerHTML = `<option value="ALL">Severity: ALL</option>` + sevs.map(x=>`<option value="${x}">${x}</option>`).join("");
      toolSel.innerHTML = `<option value="ALL">Tool: ALL</option>` + tools.map(x=>`<option value="${x}">${x}</option>`).join("");

      if ([...sevSel.options].some(o=>o.value===curSev)) sevSel.value=curSev; else { sevSel.value="ALL"; state.sev="ALL"; }
      if ([...toolSel.options].some(o=>o.value===curTool)) toolSel.value=curTool; else { toolSel.value="ALL"; state.tool="ALL"; }
    };

    const bindRows=(table)=>{
      const tbody=table.querySelector("tbody");
      if (!tbody) return;
      const trs=[...tbody.querySelectorAll("tr")];
      state.rows=[];
      for (const tr of trs){
        const obj=parseRow(tr);
        if (!obj) continue;
        state.rows.push({tr, obj});
        // row click => modal
        tr.style.cursor="pointer";
        tr.addEventListener("click",(e)=>{
          // avoid clicking links if any
          const a=e.target && e.target.closest && e.target.closest("a");
          if (a) return;
          showModal(obj);
        });
      }
    };

    const enhance=()=>{
      const t=findTopTable();
      if (!t) return false;
      buildBar(t);
      bindRows(t);
      refreshOptions();
      applyFilter();
      return true;
    };

    // Re-run enhancer when table content changes (after clicking "Load top findings")
    const attachObserver=()=>{
      const root=document.body;
      const obs=new MutationObserver(()=>{
        const t=findTopTable();
        if (!t) return;
        // refresh binding if row count changed
        const tbody=t.querySelector("tbody");
        const rc=tbody ? tbody.querySelectorAll("tr").length : 0;
        const cur=state.rows.length;
        if (rc && rc !== cur){
          bindRows(t);
          refreshOptions();
          applyFilter();
        }
      });
      obs.observe(root, {subtree:true, childList:true});
    };

    const boot=()=>{
      if (!(location && location.pathname==="/vsp5")) return;
      ensureStyle();
      ensureModal();
      let n=0;
      const t=setInterval(()=>{
        n++;
        if (enhance()){
          clearInterval(t);
          attachObserver();
        }
        if (n>140) clearInterval(t);
      }, 250);
    };

    if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_TOPFINDINGS_UX_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_TOPFINDINGS_UX_FILTER_MODAL_V1 ===================== */
""").rstrip()+"\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Top findings bar (filter/search) + click-row modal enabled."
