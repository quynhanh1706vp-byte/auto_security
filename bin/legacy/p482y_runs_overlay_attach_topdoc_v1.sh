#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482y_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p482y_${TS}"
echo "[OK] backup => ${F}.bak_p482y_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482Y_RUNS_OVERLAY_TOPDOC_WATCHDOG_V1"
if MARK in s:
    print("[OK] already patched P482y (marker found)")
    raise SystemExit(0)

js=r"""
/* ===== VSP_P482Y_RUNS_OVERLAY_TOPDOC_WATCHDOG_V1 =====
 * Fix: attach overlay to window.top.document (survive frame rebuild) + watchdog re-inject.
 */
(function(){
  const TAG="[P482y]";
  const API="/api/vsp/runs?limit=250&offset=0";

  const W = (function(){ try{ return (window.top && window.top.document) ? window.top : window; }catch(e){ return window; } })();
  const DOC = W.document || document;

  function log(){ try{ console.log(TAG, ...arguments); }catch(e){} }
  function qs(sel, root){ try{ return (root||DOC).querySelector(sel); }catch(e){ return null; } }

  const ID="vsp_runs_overlay_top_v1";
  const SID="vsp_runs_overlay_top_style_v1";

  function ensureStyle(){
    if(qs("#"+SID)) return;
    const st=DOC.createElement("style");
    st.id=SID;
    st.textContent=`
      #${ID}{
        position: fixed;
        z-index: 2147483647;
        top: 76px;
        left: 220px;
        right: 16px;
        bottom: 16px;
        border-radius: 14px;
        border: 1px solid rgba(255,255,255,.14);
        background: rgba(10,14,24,.92);
        box-shadow: 0 20px 60px rgba(0,0,0,.55);
        overflow: hidden;
        display: block !important;
      }
      #${ID} .hdr{
        display:flex; align-items:center; justify-content:space-between;
        gap:10px; padding:10px 12px;
        border-bottom:1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.03);
      }
      #${ID} .hdr .left{ display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
      #${ID} .hdr .title{ font-weight:700; font-size:12px; color: rgba(255,255,255,.92); }
      #${ID} .hdr input{
        font-size:12px; padding:6px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.14);
        background: rgba(0,0,0,.25); color: rgba(255,255,255,.92);
        width: 360px; max-width: 42vw;
      }
      #${ID} .hdr select, #${ID} .hdr button{
        font-size:12px; padding:6px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.14);
        background: rgba(255,255,255,.06); color: rgba(255,255,255,.92);
        cursor:pointer;
      }
      #${ID} .hdr .meta{ font-size:11px; color: rgba(255,255,255,.65); }
      #${ID} .body{ height: calc(100% - 48px); overflow:auto; }
      #${ID} table{ width:100%; border-collapse:collapse; }
      #${ID} thead th{
        position: sticky; top: 0;
        font-size:12px; text-align:left; padding:10px;
        color: rgba(255,255,255,.72);
        background: rgba(255,255,255,.04);
        border-bottom:1px solid rgba(255,255,255,.10);
      }
      #${ID} tbody td{
        font-size:12px; padding:9px 10px;
        border-bottom:1px solid rgba(255,255,255,.07);
        color: rgba(255,255,255,.88);
      }
      #${ID} tbody tr:hover td{ background: rgba(255,255,255,.03); }
      .mini{
        display:inline-block; margin-right:6px; margin-bottom:4px;
        font-size:11px; padding:4px 8px; border-radius:10px;
        border:1px solid rgba(255,255,255,.14);
        background: rgba(255,255,255,.06);
        color: rgba(255,255,255,.92);
        text-decoration:none;
        cursor:pointer;
      }
      .muted{ color: rgba(255,255,255,.60); }
    `;
    (DOC.head||DOC.documentElement).appendChild(st);
  }

  function normStatus(x){
    const s=String(x||"").toUpperCase();
    if(!s) return "UNKNOWN";
    if(["OK","GREEN","PASS","PASSED"].includes(s)) return "OK";
    if(["WARN","AMBER"].includes(s)) return "WARN";
    if(["FAIL","RED","ERROR","FAILED"].includes(s)) return "FAIL";
    return s;
  }
  function pick(obj, keys, dflt){
    for(const k of keys) if(obj && obj[k]!=null && obj[k]!== "") return obj[k];
    return dflt;
  }
  function pickDate(obj){
    const v=pick(obj, ["date","ts","time","started_at","ended_at","created_at"], "");
    return v ? String(v).replace("T"," ").replace("Z","") : "";
  }

  let ALL=[];
  function mount(){
    ensureStyle();
    let wrap=qs("#"+ID);
    if(wrap) return wrap;

    wrap=DOC.createElement("div");
    wrap.id=ID;
    wrap.innerHTML=`
      <div class="hdr">
        <div class="left">
          <span class="title">Runs (TOP overlay)</span>
          <input id="vsp_runs_top_q" placeholder="Search RID / status..." />
          <select id="vsp_runs_top_sort">
            <option value="date_desc">Date ↓</option>
            <option value="date_asc">Date ↑</option>
            <option value="rid_desc">RID ↓</option>
            <option value="rid_asc">RID ↑</option>
          </select>
          <span class="meta" id="vsp_runs_top_meta">...</span>
        </div>
        <div class="right">
          <button id="vsp_runs_top_reload">Reload</button>
          <button id="vsp_runs_top_hide">Hide</button>
        </div>
      </div>
      <div class="body">
        <table>
          <thead><tr>
            <th style="width:34%">RID</th>
            <th style="width:12%">STATUS</th>
            <th style="width:20%">DATE</th>
            <th style="width:34%">ACTIONS</th>
          </tr></thead>
          <tbody id="vsp_runs_top_tbody">
            <tr><td colspan="4" class="muted">Loading…</td></tr>
          </tbody>
        </table>
      </div>
    `;
    DOC.body.appendChild(wrap);

    wrap.querySelector("#vsp_runs_top_hide").addEventListener("click", ()=>{ wrap.style.display="none"; });
    wrap.querySelector("#vsp_runs_top_reload").addEventListener("click", ()=>load());
    wrap.querySelector("#vsp_runs_top_q").addEventListener("input", ()=>render());
    wrap.querySelector("#vsp_runs_top_sort").addEventListener("change", ()=>render());

    // hotkey: Ctrl+Shift+O toggle
    DOC.addEventListener("keydown", (e)=>{
      if(e.ctrlKey && e.shiftKey && (e.key==="O" || e.key==="o")){
        wrap.style.display = (wrap.style.display==="none") ? "block" : "none";
      }
    });

    return wrap;
  }

  function apply(items){
    const wrap=qs("#"+ID);
    const q=(wrap.querySelector("#vsp_runs_top_q").value||"").trim().toLowerCase();
    const sort=wrap.querySelector("#vsp_runs_top_sort").value;
    let out=items.slice();
    if(q) out=out.filter(it=>(it._rid+" "+it._status+" "+it._date).toLowerCase().includes(q));
    out.sort((a,b)=>{
      if(sort==="date_asc") return (a._date||"").localeCompare(b._date||"");
      if(sort==="rid_desc") return (b._rid||"").localeCompare(a._rid||"");
      if(sort==="rid_asc")  return (a._rid||"").localeCompare(b._rid||"");
      return (b._date||"").localeCompare(a._date||"");
    });
    return out;
  }

  function render(){
    const wrap=qs("#"+ID);
    if(!wrap) return;
    const tbody=wrap.querySelector("#vsp_runs_top_tbody");
    const meta=wrap.querySelector("#vsp_runs_top_meta");
    const vis=apply(ALL);
    meta.textContent=`total=${ALL.length} shown=${vis.length} (Ctrl+Shift+O toggle)`;

    if(!vis.length){
      tbody.innerHTML=`<tr><td colspan="4" class="muted">No runs match.</td></tr>`;
      return;
    }
    tbody.innerHTML="";
    for(const it of vis){
      const tr=DOC.createElement("tr");
      tr.innerHTML=`
        <td><div style="font-weight:700">${it._rid}</div></td>
        <td>${it._status}</td>
        <td class="muted">${it._date}</td>
        <td></td>
      `;
      const td=tr.children[3];

      const use=DOC.createElement("span");
      use.className="mini";
      use.textContent="Use RID";
      use.addEventListener("click", ()=>{
        try{ W.localStorage.setItem("VSP_PIN_RID", it._rid); }catch(e){}
        try{ W.location.reload(); }catch(e){ location.reload(); }
      });

      const dash=DOC.createElement("a");
      dash.className="mini";
      dash.textContent="Dashboard";
      dash.href="/c/dashboard?rid="+encodeURIComponent(it._rid);

      const csv=DOC.createElement("a");
      csv.className="mini";
      csv.textContent="CSV";
      csv.href="/api/vsp/export_csv?rid="+encodeURIComponent(it._rid);

      td.appendChild(use); td.appendChild(dash); td.appendChild(csv);
      tbody.appendChild(tr);
    }
  }

  async function load(){
    const wrap=mount();
    wrap.style.display="block";
    wrap.querySelector("#vsp_runs_top_tbody").innerHTML=`<tr><td colspan="4" class="muted">Loading…</td></tr>`;
    try{
      const r=await W.fetch(API,{credentials:"same-origin"});
      const j=await r.json();
      const items=(j && (j.items||j.data||j.runs||[]))||[];
      const norm=[];
      for(const x of items){
        const rid=String(pick(x,["rid","RID","run_id","id"],"")||"");
        if(!rid) continue;
        norm.push({_rid:rid,_status:normStatus(pick(x,["status","overall","verdict","gate","result"],"UNKNOWN")), _date:pickDate(x)});
      }
      ALL=norm;
      log("top overlay fetched items=", items.length, "norm=", norm.length);
      render();
    }catch(e){
      log("top overlay load err", e);
      wrap.querySelector("#vsp_runs_top_tbody").innerHTML=`<tr><td colspan="4" class="muted">Failed to load runs.</td></tr>`;
    }
  }

  function watchdog(){
    // re-inject if frame rebuild nukes it
    try{
      const wrap=qs("#"+ID);
      if(!wrap){
        log("overlay missing -> re-mount");
        load();
      }else{
        // keep it visible unless user explicitly hid it
        // (if you want always-on, uncomment next line)
        // wrap.style.display="block";
      }
    }catch(e){}
  }

  function boot(){
    try{
      const p = (function(){ try{ return W.location.pathname || location.pathname; }catch(e){ return location.pathname; } })();
      if(p.indexOf("/c/runs")<0 && p.indexOf("/runs")<0) return;
      load();
      setInterval(watchdog, 800);
      // also run once after frame settles
      setTimeout(watchdog, 1200);
      setTimeout(watchdog, 2400);
    }catch(e){ log("boot err", e); }
  }

  if(DOC.readyState==="loading") DOC.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
p.write_text(s.rstrip()+"\n\n"+js+"\n", encoding="utf-8")
print("[OK] appended P482y (topdoc overlay + watchdog) into vsp_c_runs_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 3; }
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || sudo systemctl restart "$SVC"
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P482y done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] toggle overlay: Ctrl+Shift+O" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
