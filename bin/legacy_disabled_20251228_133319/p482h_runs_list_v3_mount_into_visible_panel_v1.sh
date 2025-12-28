#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482h_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p482h_${TS}"
echo "[OK] backup => ${F}.bak_p482h_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482H_RUNS_LIST_V3_MOUNT_INTO_VISIBLE_PANEL_V1"
if MARK in s:
    print("[OK] already patched P482h (marker found)")
    raise SystemExit(0)

js=r"""
/* ===== {MARK} =====
 * Fix blank /c/runs: mount Runs List V3 into the *visible content panel* (not body-firstchild).
 * Also prefer the largest visible same-origin iframe if present.
 */
(function(){
  const TAG="[P482h]";
  const API="/api/vsp/runs?limit=250&offset=0";
  const LS_KEYS=["VSP_PIN_RID","VSP_RID","VSP_LAST_RID","RID","vsp_rid"];

  function log(){ try{ console.log.apply(console,[TAG].concat([].slice.call(arguments))); }catch(e){} }
  function qsa(sel, root){ try{ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }catch(e){ return []; } }
  function qs(sel, root){ try{ return (root||document).querySelector(sel); }catch(e){ return null; } }

  function removeWrapEverywhere(){
    try{ qsa("#vsp_runs_v3_wrap").forEach(x=>x.remove()); }catch(e){}
    try{
      qsa("iframe").forEach(fr=>{
        try{
          const d=fr.contentDocument; if(!d) return;
          const w=d.querySelector("#vsp_runs_v3_wrap"); if(w) w.remove();
          const st=d.querySelector("#vsp_runs_v3_style"); if(st) st.remove();
        }catch(e){}
      });
    }catch(e){}
  }

  function isVisibleIframe(fr){
    try{
      const st=getComputedStyle(fr);
      if(st.display==="none" || st.visibility==="hidden" || Number(st.opacity||"1")<=0) return false;
      const r=fr.getBoundingClientRect();
      return (r.width>200 && r.height>200);
    }catch(e){ return false; }
  }

  function pickBestDoc(){
    // prefer largest visible iframe (same-origin) otherwise current doc
    let best={doc:document, area:(window.innerWidth*window.innerHeight), why:"self"};
    const ifs=qsa("iframe");
    for(const fr of ifs){
      if(!isVisibleIframe(fr)) continue;
      let d=null;
      try{ d=fr.contentDocument; }catch(e){ d=null; }
      if(!d || !d.body) continue;
      const r=fr.getBoundingClientRect();
      let area=r.width*r.height;
      const src=(fr.getAttribute("src")||"").toLowerCase();
      if(src.includes("/runs")) area += 1e9; // strong bias if looks like content frame for runs
      if(area>best.area){
        best={doc:d, area, why:"iframe"};
      }
    }
    log("pick doc:", best.why, "area=", best.area);
    return best.doc;
  }

  function findHost(d){
    // 1) best-known containers
    const sels=[
      "#vsp_tab_body","#vsp_main","#vsp_content","#content","main",
      ".vsp-main",".vsp-content",".tab-body",".page-body",".content-body",
      ".container",".panel",".card"
    ];
    for(const sel of sels){
      const el=qs(sel,d);
      if(el && el.getBoundingClientRect && el.getBoundingClientRect().height>120) return el;
    }

    // 2) find element containing "Runs & Reports" then choose its nearest section-ish parent
    const nodes=qsa("div,section,article,main", d);
    for(const el of nodes){
      const t=((el.innerText||"").trim().replace(/\s+/g," ")).toLowerCase();
      if(t.includes("runs & reports") || t.includes("runs and reports")){
        // walk up a bit to find a reasonable panel
        let cur=el;
        for(let i=0;i<6 && cur && cur.parentElement;i++){
          const r=cur.getBoundingClientRect();
          if(r.height>200 && r.width>300) return cur;
          cur=cur.parentElement;
        }
        return el;
      }
    }

    // 3) fallback: first big block in body
    const bodyKids=Array.prototype.slice.call(d.body.children||[]);
    let best=null, bestArea=0;
    for(const el of bodyKids){
      const r=el.getBoundingClientRect();
      const area=r.width*r.height;
      if(area>bestArea){ bestArea=area; best=el; }
    }
    return best || d.body;
  }

  function ensureStyle(d){
    if(qs("#vsp_runs_v3_style",d)) return;
    const st=d.createElement("style");
    st.id="vsp_runs_v3_style";
    st.textContent=`
      .vsp-runs-v3-wrap{ margin: 10px 0 14px 0; position: relative; z-index: 9999; }
      .vsp-runs-v3-toolbar{ position: sticky; top: 8px; z-index: 10000; backdrop-filter: blur(6px); }
      .vsp-runs-v3-bar{ display:flex; gap:8px; align-items:center; justify-content:space-between; padding:10px 12px; border-radius:12px;
        border:1px solid rgba(255,255,255,.08); background: rgba(10,14,24,.55); }
      .vsp-runs-v3-left{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp-runs-v3-chip{ font-size:12px; padding:4px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.10);
        color: rgba(255,255,255,.86); cursor:pointer; user-select:none; }
      .vsp-runs-v3-chip[data-on="1"]{ border-color: rgba(255,255,255,.28); background: rgba(255,255,255,.06); }
      .vsp-runs-v3-input{ min-width: 280px; max-width: 520px; width: 36vw;
        font-size:12px; padding:6px 10px; border-radius:10px; outline:none;
        border:1px solid rgba(255,255,255,.10); background: rgba(0,0,0,.25); color: rgba(255,255,255,.90); }
      .vsp-runs-v3-right{ display:flex; gap:8px; align-items:center; }
      .vsp-runs-v3-sel{ font-size:12px; padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.10);
        background: rgba(0,0,0,.25); color: rgba(255,255,255,.90); }
      .vsp-runs-v3-btn{ font-size:12px; padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.05); color: rgba(255,255,255,.90); cursor:pointer; }
      .vsp-runs-v3-tablewrap{ margin-top:10px; border-radius:12px; overflow:hidden; border:1px solid rgba(255,255,255,.08); }
      .vsp-runs-v3-table{ width:100%; border-collapse: collapse; }
      .vsp-runs-v3-table thead th{ font-size:12px; text-align:left; padding:10px 10px; color: rgba(255,255,255,.70);
        background: rgba(255,255,255,.03); border-bottom:1px solid rgba(255,255,255,.08); }
      .vsp-runs-v3-table tbody td{ font-size:12px; padding:9px 10px; border-bottom:1px solid rgba(255,255,255,.06);
        color: rgba(255,255,255,.85); vertical-align: top; }
      .vsp-runs-v3-table tbody tr:hover td{ background: rgba(255,255,255,.03); }
      .vsp-runs-v3-actions{ display:flex; gap:6px; flex-wrap:wrap; }
      .vsp-runs-v3-mini{ font-size:11px; padding:4px 8px; border-radius:10px; border:1px solid rgba(255,255,255,.12);
        background: rgba(255,255,255,.04); color: rgba(255,255,255,.88); cursor:pointer; text-decoration:none; }
      .vsp-runs-v3-muted{ color: rgba(255,255,255,.55); }
    `;
    (d.head||d.documentElement).appendChild(st);
  }

  function setRid(rid){
    try{ LS_KEYS.forEach(k=>{ try{ localStorage.setItem(k,String(rid)); }catch(e){} }); }catch(e){}
  }

  function normStatus(x){
    const s=String(x||"").toUpperCase();
    if(!s) return "UNKNOWN";
    if(["OK","GREEN","PASS","PASSED"].includes(s)) return "OK";
    if(["WARN","AMBER"].includes(s)) return "WARN";
    if(["FAIL","RED","ERROR","FAILED"].includes(s)) return "FAIL";
    if(["UNKNOWN","NA","N/A","NONE"].includes(s)) return "UNKNOWN";
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

  let LAST=[];
  function mount(d){
    ensureStyle(d);
    if(qs("#vsp_runs_v3_wrap",d)) return;

    const host=findHost(d);
    log("host=", host && (host.id||host.className||host.tagName));

    const wrap=d.createElement("div");
    wrap.id="vsp_runs_v3_wrap";
    wrap.className="vsp-runs-v3-wrap";
    wrap.innerHTML=`
      <div class="vsp-runs-v3-toolbar">
        <div class="vsp-runs-v3-bar">
          <div class="vsp-runs-v3-left">
            <span class="vsp-runs-v3-chip" data-k="ALL" data-on="1">ALL</span>
            <span class="vsp-runs-v3-chip" data-k="OK" data-on="0">OK</span>
            <span class="vsp-runs-v3-chip" data-k="WARN" data-on="0">WARN</span>
            <span class="vsp-runs-v3-chip" data-k="FAIL" data-on="0">FAIL</span>
            <span class="vsp-runs-v3-chip" data-k="UNKNOWN" data-on="0">UNKNOWN</span>
            <input class="vsp-runs-v3-input" id="vsp_runs_v3_q" placeholder="Search RID / status / anything..." />
          </div>
          <div class="vsp-runs-v3-right">
            <select class="vsp-runs-v3-sel" id="vsp_runs_v3_sort">
              <option value="date_desc">Date ↓ (newest)</option>
              <option value="date_asc">Date ↑ (oldest)</option>
              <option value="rid_desc">RID ↓</option>
              <option value="rid_asc">RID ↑</option>
            </select>
            <span class="vsp-runs-v3-muted" id="vsp_runs_v3_count">...</span>
            <button class="vsp-runs-v3-btn" id="vsp_runs_v3_reload">Reload</button>
          </div>
        </div>
      </div>

      <div class="vsp-runs-v3-tablewrap">
        <table class="vsp-runs-v3-table">
          <thead><tr>
            <th style="width:32%">RID</th>
            <th style="width:12%">STATUS</th>
            <th style="width:20%">DATE</th>
            <th style="width:36%">ACTIONS</th>
          </tr></thead>
          <tbody id="vsp_runs_v3_tbody">
            <tr><td colspan="4" class="vsp-runs-v3-muted">Loading…</td></tr>
          </tbody>
        </table>
      </div>
    `;

    // insert at top of host (not body)
    try{
      if(host && host.firstChild) host.insertBefore(wrap, host.firstChild);
      else (host||d.body).appendChild(wrap);
    }catch(e){
      d.body.appendChild(wrap);
    }

    const chips=Array.prototype.slice.call(wrap.querySelectorAll(".vsp-runs-v3-chip"));
    chips.forEach(ch=>{
      ch.addEventListener("click", ()=>{
        const k=ch.getAttribute("data-k");
        if(k==="ALL"){
          chips.forEach(x=>x.setAttribute("data-on", x.getAttribute("data-k")==="ALL" ? "1":"0"));
        }else{
          wrap.querySelector('.vsp-runs-v3-chip[data-k="ALL"]').setAttribute("data-on","0");
          ch.setAttribute("data-on", ch.getAttribute("data-on")==="1" ? "0":"1");
        }
        render(d, LAST);
      });
    });
    wrap.querySelector("#vsp_runs_v3_q").addEventListener("input", ()=>render(d, LAST));
    wrap.querySelector("#vsp_runs_v3_sort").addEventListener("change", ()=>render(d, LAST));
    wrap.querySelector("#vsp_runs_v3_reload").addEventListener("click", ()=>load(d));
  }

  function applyFilters(d, items){
    const wrap=qs("#vsp_runs_v3_wrap",d);
    if(!wrap) return items;
    const q=(wrap.querySelector("#vsp_runs_v3_q").value||"").trim().toLowerCase();
    const chips=Array.prototype.slice.call(wrap.querySelectorAll(".vsp-runs-v3-chip"))
      .filter(x=>x.getAttribute("data-on")==="1").map(x=>x.getAttribute("data-k"));
    const active=chips.length?chips:["ALL"];

    let out=items.slice();
    if(active.indexOf("ALL")<0) out=out.filter(it=>active.indexOf(it._status)>=0);
    if(q) out=out.filter(it=>(it._rid+" "+it._status+" "+it._date+" "+it._raw).toLowerCase().includes(q));

    const sort=wrap.querySelector("#vsp_runs_v3_sort").value;
    out.sort((a,b)=>{
      if(sort==="date_asc") return (a._date||"").localeCompare(b._date||"");
      if(sort==="rid_desc") return (b._rid||"").localeCompare(a._rid||"");
      if(sort==="rid_asc")  return (a._rid||"").localeCompare(b._rid||"");
      return (b._date||"").localeCompare(a._date||"");
    });
    return out;
  }

  function render(d, items){
    LAST=items||LAST||[];
    const wrap=qs("#vsp_runs_v3_wrap",d);
    if(!wrap) return;
    const tbody=wrap.querySelector("#vsp_runs_v3_tbody");
    const count=wrap.querySelector("#vsp_runs_v3_count");

    const vis=applyFilters(d, LAST);
    count.textContent=`total=${LAST.length} shown=${vis.length}`;

    if(!vis.length){
      tbody.innerHTML=`<tr><td colspan="4" class="vsp-runs-v3-muted">No runs match filters.</td></tr>`;
      return;
    }

    tbody.innerHTML="";
    for(const it of vis){
      const tr=d.createElement("tr");
      tr.innerHTML=`
        <td><div style="font-weight:600">${it._rid||""}</div></td>
        <td>${it._status||"UNKNOWN"}</td>
        <td class="vsp-runs-v3-muted">${it._date||""}</td>
        <td><div class="vsp-runs-v3-actions"></div></td>
      `;
      const act=tr.querySelector(".vsp-runs-v3-actions");

      const use=d.createElement("span");
      use.className="vsp-runs-v3-mini";
      use.textContent="Use RID";
      use.addEventListener("click", ()=>{ setRid(it._rid); window.location.reload(); });

      const dash=d.createElement("a");
      dash.className="vsp-runs-v3-mini";
      dash.textContent="Dashboard";
      dash.href="/c/dashboard?rid="+encodeURIComponent(it._rid);
      dash.addEventListener("click", ()=>{ try{ setRid(it._rid); }catch(e){} });

      const csv=d.createElement("a");
      csv.className="vsp-runs-v3-mini";
      csv.textContent="CSV";
      csv.href="/api/vsp/export_csv?rid="+encodeURIComponent(it._rid);

      const sum=d.createElement("a");
      sum.className="vsp-runs-v3-mini";
      sum.textContent="Summary";
      sum.href="/api/vsp/run_file_allow?rid="+encodeURIComponent(it._rid)+"&path="+encodeURIComponent("reports/run_gate_summary.json");

      act.appendChild(use); act.appendChild(dash); act.appendChild(csv); act.appendChild(sum);
      tbody.appendChild(tr);
    }
  }

  async function load(d){
    mount(d);
    const wrap=qs("#vsp_runs_v3_wrap",d);
    if(!wrap) return;
    wrap.querySelector("#vsp_runs_v3_tbody").innerHTML=`<tr><td colspan="4" class="vsp-runs-v3-muted">Loading…</td></tr>`;
    try{
      const r=await fetch(API,{credentials:"same-origin"});
      const j=await r.json();
      const items=(j && (j.items||j.data||j.runs||[]))||[];
      const norm=[];
      for(const x of items){
        const rid=String(pick(x,["rid","RID","run_id","id"],"")||"");
        if(!rid) continue;
        const st=normStatus(pick(x,["status","overall","verdict","gate","result"],"UNKNOWN"));
        const dt=pickDate(x);
        norm.push({_rid:rid,_status:st,_date:dt,_raw:JSON.stringify(x).slice(0,4000)});
      }
      log("runs fetched items=", items.length, "norm=", norm.length);
      render(d, norm);
      log("runs list v3 ready (target doc)");
    }catch(e){
      log("load err", e);
      wrap.querySelector("#vsp_runs_v3_tbody").innerHTML=`<tr><td colspan="4" class="vsp-runs-v3-muted">Failed to load runs.</td></tr>`;
    }
  }

  function boot(){
    try{
      if(location.pathname.indexOf("/c/runs")<0 && location.pathname.indexOf("/runs")<0) return;
      removeWrapEverywhere();
      const d=pickBestDoc();
      let tries=0;
      const tick=()=>{
        tries++;
        try{
          if(!d || !d.body || d.body.childElementCount===0){
            if(tries<40) return setTimeout(tick,150);
          }
          load(d);
        }catch(e){
          if(tries<40) return setTimeout(tick,150);
          log("boot err", e);
        }
      };
      tick();
    }catch(e){ log("boot outer err", e); }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
""".replace("{MARK}", MARK)

p.write_text(s.rstrip()+"\n\n"+js+"\n", encoding="utf-8")
print("[OK] appended P482h block into vsp_c_runs_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 3; }
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || sudo systemctl restart "$SVC"
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P482h done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
