#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_common_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p481_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p481_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P481_DS_POLISH_STICKY_FILTER_DRAWER_V1"
if MARK in s:
    print("[OK] already patched P481")
else:
    add=r"""

/* VSP_P481_DS_POLISH_STICKY_FILTER_DRAWER_V1 */
(function(){
  if (window.__VSP_P481__) return;
  window.__VSP_P481__ = 1;

  const LEVELS = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function onDS(){ return location.pathname.includes("/c/data_source"); }

  function css(){
    if(document.getElementById("vsp_p481_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p481_css";
    st.textContent=`
/* hide accidental huge raw table above (best-effort) */
.vsp_p481_hide_dup_block{display:none!important}

/* chips */
#vsp_p481_bar{
  margin:10px 0 12px 0;
  display:flex;gap:8px;flex-wrap:wrap;align-items:center;
}
.vsp_p481_chip{
  border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.86);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
  user-select:none;
}
.vsp_p481_chip.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
.vsp_p481_sep{opacity:.35;margin:0 4px}

/* sticky header for main DS table */
.vsp_p481_table_wrap{
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  overflow:hidden;
}
.vsp_p481_table_scroller{
  max-height: 62vh;
  overflow:auto;
}
.vsp_p481_table_scroller table{ width:100%; border-collapse:collapse; }
.vsp_p481_table_scroller thead th{
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(20,24,33,0.98);
  backdrop-filter: blur(6px);
  border-bottom:1px solid rgba(255,255,255,0.06);
}
.vsp_p481_table_scroller td, .vsp_p481_table_scroller th{
  padding:8px 10px;
  font-size:12px;
  text-align:left;
  border-bottom:1px solid rgba(255,255,255,0.05);
}
.vsp_p481_row{ cursor:pointer; }
.vsp_p481_row:hover{ background:rgba(255,255,255,0.03); }

/* drawer */
#vsp_p481_drawer_backdrop{
  position:fixed; inset:0;
  background:rgba(0,0,0,0.55);
  z-index: 9998;
}
#vsp_p481_drawer{
  position:fixed; top:0; right:0;
  height:100vh; width: 520px; max-width: 92vw;
  z-index: 9999;
  border-left:1px solid rgba(255,255,255,0.08);
  background: rgba(12,16,24,0.98);
  backdrop-filter: blur(8px);
  padding:14px 14px;
  overflow:auto;
}
#vsp_p481_drawer .t{font-weight:900;font-size:14px;letter-spacing:.2px}
#vsp_p481_drawer .x{
  margin-top:10px; opacity:.86; font-size:12px; line-height:1.6;
}
#vsp_p481_drawer .kv{
  border:1px solid rgba(255,255,255,0.08);
  border-radius:14px;
  background:rgba(255,255,255,0.02);
  padding:10px 12px;
  margin-top:10px;
}
#vsp_p481_drawer .k{opacity:.65;font-size:11px}
#vsp_p481_drawer .v{margin-top:4px;font-size:12px;word-break:break-word}
#vsp_p481_drawer button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:7px 10px;
  font-size:12px;
}
#vsp_p481_drawer button:hover{background:rgba(255,255,255,0.06)}
#vsp_p481_drawer .btns{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
`;
    document.head.appendChild(st);
  }

  function hideHugeRawDuplicate(){
    // Some pages render a giant raw table above the framed content; hide it if it looks like a duplicate findings table
    try{
      const frame = document.querySelector(".vsp_p473_frame");
      if(!frame) return;
      // Look for large tables outside frame
      const tables = Array.from(document.querySelectorAll("table"));
      for(const tb of tables){
        if(frame.contains(tb)) continue;
        const rows = tb.querySelectorAll("tr").length;
        const cols = tb.querySelectorAll("th,td").length;
        if(rows > 15 && cols > 30){
          const wrap = tb.closest("div,section") || tb;
          wrap.classList.add("vsp_p481_hide_dup_block");
          console.log("[P481] hid duplicate raw table block");
          return;
        }
      }
    }catch(e){}
  }

  function findMainCard(){
    // best-effort: find the "Data Source" card inside frame
    const frame = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap");
    if(!frame) return null;
    // pick the first card-like block that contains "Data Source" text and has a table
    const nodes = Array.from(frame.querySelectorAll("div,section"));
    for(const n of nodes){
      const txt=(n.innerText||"");
      if(txt.includes("Data Source") && n.querySelector("table")){
        return n;
      }
    }
    // fallback: any table inside frame
    const t = frame.querySelector("table");
    return t ? (t.closest("div,section") || frame) : null;
  }

  function makeChipsBar(onChange){
    const bar=document.createElement("div");
    bar.id="vsp_p481_bar";
    const state={ level:null, tool:null };

    function chip(label, key, val){
      const c=document.createElement("span");
      c.className="vsp_p481_chip";
      c.textContent=label;
      c.onclick=()=>{
        if(state[key]===val){ state[key]=null; c.classList.remove("on"); }
        else{
          // turn off other chips of same key
          bar.querySelectorAll(`.vsp_p481_chip[data-key="${key}"]`).forEach(x=>x.classList.remove("on"));
          state[key]=val; c.classList.add("on");
        }
        onChange({...state});
      };
      c.dataset.key=key;
      return c;
    }

    LEVELS.forEach(l=>bar.appendChild(chip(l,"level",l)));
    const sep=document.createElement("span"); sep.className="vsp_p481_sep"; sep.textContent="|";
    bar.appendChild(sep);

    const toolInput=document.createElement("input");
    toolInput.placeholder="Filter tool (e.g. grype, semgrep)...";
    toolInput.style.cssText="flex:1;min-width:220px;border-radius:12px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.02);color:rgba(255,255,255,0.9);padding:7px 10px;font-size:12px;";
    toolInput.oninput=()=>{
      state.tool = toolInput.value.trim() || null;
      onChange({...state});
    };
    bar.appendChild(toolInput);

    return {bar, state};
  }

  function wrapTableForSticky(table){
    const wrap=document.createElement("div");
    wrap.className="vsp_p481_table_wrap";
    const sc=document.createElement("div");
    sc.className="vsp_p481_table_scroller";
    table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(sc);
    sc.appendChild(table);
  }

  function openDrawer(rowObj){
    closeDrawer();
    const bd=document.createElement("div");
    bd.id="vsp_p481_drawer_backdrop";
    bd.onclick=closeDrawer;

    const dr=document.createElement("div");
    dr.id="vsp_p481_drawer";

    const t=document.createElement("div");
    t.className="t";
    t.textContent="Finding details";
    dr.appendChild(t);

    const btns=document.createElement("div");
    btns.className="btns";
    const b1=document.createElement("button");
    b1.textContent="Copy JSON";
    b1.onclick=()=>{
      try{ navigator.clipboard.writeText(JSON.stringify(rowObj,null,2)); }catch(e){}
    };
    const b2=document.createElement("button");
    b2.textContent="Close";
    b2.onclick=closeDrawer;
    btns.appendChild(b1); btns.appendChild(b2);
    dr.appendChild(btns);

    const x=document.createElement("div");
    x.className="x";
    x.textContent="Click outside to close. Use Copy JSON to attach evidence into ticket.";
    dr.appendChild(x);

    // render kv
    const keys=Object.keys(rowObj||{});
    keys.forEach(k=>{
      const kv=document.createElement("div");
      kv.className="kv";
      const kk=document.createElement("div");
      kk.className="k"; kk.textContent=k;
      const vv=document.createElement("div");
      vv.className="v"; vv.textContent=(rowObj[k]==null?"":String(rowObj[k]));
      kv.appendChild(kk); kv.appendChild(vv);
      dr.appendChild(kv);
    });

    document.body.appendChild(bd);
    document.body.appendChild(dr);
  }

  function closeDrawer(){
    const bd=document.getElementById("vsp_p481_drawer_backdrop");
    const dr=document.getElementById("vsp_p481_drawer");
    if(bd) bd.remove();
    if(dr) dr.remove();
  }

  function parseRow(tr){
    // build object from cells; prefer header names
    const table=tr.closest("table");
    if(!table) return null;
    const ths=Array.from(table.querySelectorAll("thead th")).map(x=>(x.innerText||"").trim()||"col");
    const tds=Array.from(tr.querySelectorAll("td")).map(x=>(x.innerText||"").trim());
    const obj={};
    for(let i=0;i<tds.length;i++){
      const key = ths[i] || ("col"+i);
      obj[key]=tds[i];
    }
    return obj;
  }

  function applyFilter(table, st){
    const rows=Array.from(table.querySelectorAll("tbody tr"));
    let shown=0;
    rows.forEach(tr=>{
      const txt=(tr.innerText||"").toUpperCase();
      let ok=true;
      if(st.level){
        ok = ok && txt.includes(st.level);
      }
      if(st.tool){
        ok = ok && txt.toLowerCase().includes(st.tool.toLowerCase());
      }
      tr.style.display = ok ? "" : "none";
      if(ok) shown++;
    });
    console.log("[P481] filter", st, "shown", shown);
  }

  function boot(){
    if(!onDS()) return;
    css();
    hideHugeRawDuplicate();

    const card=findMainCard();
    if(!card){ console.log("[P481] no ds card/table found"); return; }

    const table=card.querySelector("table");
    if(!table){ console.log("[P481] no table"); return; }

    // insert chips bar above table
    if(!document.getElementById("vsp_p481_bar")){
      const {bar} = makeChipsBar((st)=>applyFilter(table, st));
      table.parentNode.insertBefore(bar, table);
    }

    // wrap for sticky header
    if(!table.closest(".vsp_p481_table_wrap")){
      wrapTableForSticky(table);
    }

    // click row -> drawer
    const rows=Array.from(table.querySelectorAll("tbody tr"));
    rows.forEach(tr=>{
      tr.classList.add("vsp_p481_row");
      tr.addEventListener("click", ()=>{
        const obj=parseRow(tr) || {};
        openDrawer(obj);
      });
    });

    // ESC close
    document.addEventListener("keydown", (e)=>{ if(e.key==="Escape") closeDrawer(); });

    console.log("[P481] datasource polish ready");
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 350));
  else setTimeout(boot, 350);
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P481 into vsp_c_common_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P481 done. Reopen /c/data_source then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
