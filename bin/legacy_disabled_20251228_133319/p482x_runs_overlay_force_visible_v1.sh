#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482x_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p482x_${TS}"
echo "[OK] backup => ${F}.bak_p482x_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482X_RUNS_OVERLAY_FORCE_VISIBLE_V1"
if MARK in s:
    print("[OK] already patched P482x (marker found)")
    raise SystemExit(0)

js=r"""
/* ===== VSP_P482X_RUNS_OVERLAY_FORCE_VISIBLE_V1 =====
 * Emergency: force visible Runs list via fixed overlay (bypass layout/overflow/z-index issues).
 */
(function(){
  const TAG="[P482x]";
  const API="/api/vsp/runs?limit=250&offset=0";

  function log(){ try{ console.log(TAG, ...arguments); }catch(e){} }
  function qs(sel, root){ try{ return (root||document).querySelector(sel); }catch(e){ return null; } }

  function killOld(){
    try{
      const el=document.getElementById("vsp_runs_overlay_v1");
      if(el) el.remove();
      const st=document.getElementById("vsp_runs_overlay_style_v1");
      if(st) st.remove();
    }catch(e){}
  }

  function ensureStyle(){
    if(qs("#vsp_runs_overlay_style_v1")) return;
    const st=document.createElement("style");
    st.id="vsp_runs_overlay_style_v1";
    st.textContent=`
      #vsp_runs_overlay_v1{
        position: fixed;
        z-index: 2147483647;
        top: 64px;
        left: 220px;   /* sidebar width-ish */
        right: 16px;
        bottom: 16px;
        border-radius: 14px;
        border: 1px solid rgba(255,255,255,.14);
        background: rgba(10,14,24,.92);
        box-shadow: 0 20px 60px rgba(0,0,0,.55);
        overflow: hidden;
        display: none;
      }
      #vsp_runs_overlay_v1[data-on="1"]{ display: block; }
      #vsp_runs_overlay_v1 .hdr{
        display:flex; align-items:center; justify-content:space-between;
        gap:10px; padding:10px 12px;
        border-bottom:1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.03);
      }
      #vsp_runs_overlay_v1 .hdr .left{ display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
      #vsp_runs_overlay_v1 .hdr .title{ font-weight:700; font-size:12px; color: rgba(255,255,255,.92); }
      #vsp_runs_overlay_v1 .hdr input{
        font-size:12px; padding:6px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.14);
        background: rgba(0,0,0,.25); color: rgba(255,255,255,.92);
        width: 360px; max-width: 42vw;
      }
      #vsp_runs_overlay_v1 .hdr select, #vsp_runs_overlay_v1 .hdr button{
        font-size:12px; padding:6px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.14);
        background: rgba(255,255,255,.06); color: rgba(255,255,255,.92);
        cursor:pointer;
      }
      #vsp_runs_overlay_v1 .hdr .meta{ font-size:11px; color: rgba(255,255,255,.65); }
      #vsp_runs_overlay_v1 .body{
        height: calc(100% - 48px);
        overflow: auto;
      }
      #vsp_runs_overlay_v1 table{ width:100%; border-collapse: collapse; }
      #vsp_runs_overlay_v1 thead th{
        position: sticky; top: 0;
        font-size:12px; text-align:left; padding:10px;
        color: rgba(255,255,255,.72);
        background: rgba(255,255,255,.04);
        border-bottom:1px solid rgba(255,255,255,.10);
      }
      #vsp_runs_overlay_v1 tbody td{
        font-size:12px; padding:9px 10px;
        border-bottom:1px solid rgba(255,255,255,.07);
        color: rgba(255,255,255,.88);
      }
      #vsp_runs_overlay_v1 tbody tr:hover td{ background: rgba(255,255,255,.03); }
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
    (document.head||document.documentElement).appendChild(st);
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
    if(qs("#vsp_runs_overlay_v1")) return qs("#vsp_runs_overlay_v1");
    const wrap=document.createElement("div");
    wrap.id="vsp_runs_overlay_v1";
    wrap.setAttribute("data-on","1");
    wrap.innerHTML=`
      <div class="hdr">
        <div class="left">
          <span class="title">Runs Overlay (forced visible)</span>
          <input id="vsp_runs_ov_q" placeholder="Search RID / status..." />
          <select id="vsp_runs_ov_sort">
            <option value="date_desc">Date ↓</option>
            <option value="date_asc">Date ↑</option>
            <option value="rid_desc">RID ↓</option>
            <option value="rid_asc">RID ↑</option>
          </select>
          <span class="meta" id="vsp_runs_ov_meta">...</span>
        </div>
        <div class="right">
          <button id="vsp_runs_ov_reload">Reload</button>
          <button id="vsp_runs_ov_close">Close</button>
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
          <tbody id="vsp_runs_ov_tbody">
            <tr><td colspan="4" class="muted">Loading…</td></tr>
          </tbody>
        </table>
      </div>
    `;
    document.body.appendChild(wrap);

    wrap.querySelector("#vsp_runs_ov_close").addEventListener("click", ()=>{
      wrap.setAttribute("data-on","0");
    });
    wrap.querySelector("#vsp_runs_ov_reload").addEventListener("click", ()=>load());
    wrap.querySelector("#vsp_runs_ov_q").addEventListener("input", ()=>render());
    wrap.querySelector("#vsp_runs_ov_sort").addEventListener("change", ()=>render());

    // hotkey: Ctrl+Shift+O toggle
    document.addEventListener("keydown", (e)=>{
      if(e.ctrlKey && e.shiftKey && (e.key==="O" || e.key==="o")){
        const on = wrap.getAttribute("data-on")==="1";
        wrap.setAttribute("data-on", on ? "0":"1");
      }
    });

    return wrap;
  }

  function apply(items){
    const wrap=qs("#vsp_runs_overlay_v1");
    const q=(wrap.querySelector("#vsp_runs_ov_q").value||"").trim().toLowerCase();
    const sort=wrap.querySelector("#vsp_runs_ov_sort").value;
    let out=items.slice();
    if(q){
      out=out.filter(it=>(it._rid+" "+it._status+" "+it._date).toLowerCase().includes(q));
    }
    out.sort((a,b)=>{
      if(sort==="date_asc") return (a._date||"").localeCompare(b._date||"");
      if(sort==="rid_desc") return (b._rid||"").localeCompare(a._rid||"");
      if(sort==="rid_asc")  return (a._rid||"").localeCompare(b._rid||"");
      return (b._date||"").localeCompare(a._date||"");
    });
    return out;
  }

  function render(){
    const wrap=qs("#vsp_runs_overlay_v1");
    if(!wrap) return;
    const tbody=wrap.querySelector("#vsp_runs_ov_tbody");
    const meta=wrap.querySelector("#vsp_runs_ov_meta");
    const vis=apply(ALL);
    meta.textContent=`total=${ALL.length} shown=${vis.length}  (Ctrl+Shift+O toggle)`;

    if(!vis.length){
      tbody.innerHTML=`<tr><td colspan="4" class="muted">No runs match.</td></tr>`;
      return;
    }
    tbody.innerHTML="";
    for(const it of vis){
      const tr=document.createElement("tr");
      tr.innerHTML=`
        <td><div style="font-weight:700">${it._rid}</div></td>
        <td>${it._status}</td>
        <td class="muted">${it._date}</td>
        <td></td>
      `;
      const td=tr.children[3];

      const use=document.createElement("span");
      use.className="mini";
      use.textContent="Use RID";
      use.addEventListener("click", ()=>{
        try{ localStorage.setItem("VSP_PIN_RID", it._rid); }catch(e){}
        window.location.reload();
      });

      const dash=document.createElement("a");
      dash.className="mini";
      dash.textContent="Dashboard";
      dash.href="/c/dashboard?rid="+encodeURIComponent(it._rid);

      const csv=document.createElement("a");
      csv.className="mini";
      csv.textContent="CSV";
      csv.href="/api/vsp/export_csv?rid="+encodeURIComponent(it._rid);

      const sum=document.createElement("a");
      sum.className="mini";
      sum.textContent="Summary";
      sum.href="/api/vsp/run_file_allow?rid="+encodeURIComponent(it._rid)+"&path="+encodeURIComponent("reports/run_gate_summary.json");

      td.appendChild(use); td.appendChild(dash); td.appendChild(csv); td.appendChild(sum);
      tbody.appendChild(tr);
    }
  }

  async function load(){
    const wrap=mount();
    wrap.setAttribute("data-on","1");
    wrap.querySelector("#vsp_runs_ov_tbody").innerHTML=`<tr><td colspan="4" class="muted">Loading…</td></tr>`;
    try{
      const r=await fetch(API,{credentials:"same-origin"});
      const j=await r.json();
      const items=(j && (j.items||j.data||j.runs||[]))||[];
      const norm=[];
      for(const x of items){
        const rid=String(pick(x,["rid","RID","run_id","id"],"")||"");
        if(!rid) continue;
        norm.push({_rid:rid,_status:normStatus(pick(x,["status","overall","verdict","gate","result"],"UNKNOWN")), _date:pickDate(x)});
      }
      ALL=norm;
      log("overlay runs fetched items=", items.length, "norm=", norm.length);
      render();
    }catch(e){
      log("overlay load err", e);
      wrap.querySelector("#vsp_runs_ov_tbody").innerHTML=`<tr><td colspan="4" class="muted">Failed to load runs.</td></tr>`;
    }
  }

  function boot(){
    try{
      if(location.pathname.indexOf("/c/runs")<0 && location.pathname.indexOf("/runs")<0) return;
      killOld();
      load();
    }catch(e){ log("boot err", e); }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
p.write_text(s.rstrip()+"\n\n"+js+"\n", encoding="utf-8")
print("[OK] appended P482x overlay block into vsp_c_runs_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 3; }
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || sudo systemctl restart "$SVC"
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P482x done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] tip: press Ctrl+Shift+O to toggle overlay" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
