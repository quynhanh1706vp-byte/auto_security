#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_common_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p481b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p481b_${TS}"
echo "[OK] backup => ${F}.bak_p481b_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P481B_DS_FALLBACK_FORCE_VISIBLE_V1"
if MARK in s:
    print("[OK] already patched P481b")
else:
    s += r"""

/* VSP_P481B_DS_FALLBACK_FORCE_VISIBLE_V1 */
(function(){
  if (window.__VSP_P481B__) return;
  window.__VSP_P481B__ = 1;

  const LEVELS=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function onDS(){ return location.pathname.includes("/c/data_source"); }

  function ensureCss(){
    if(document.getElementById("vsp_p481b_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p481b_css";
    st.textContent=`
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

.vsp_p481_table_wrap{
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
  overflow:hidden;
}
.vsp_p481_table_scroller{
  max-height: 66vh;
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
#vsp_p481_drawer .x{margin-top:10px;opacity:.86;font-size:12px;line-height:1.6}
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

  function closeDrawer(){
    const bd=document.getElementById("vsp_p481_drawer_backdrop");
    const dr=document.getElementById("vsp_p481_drawer");
    if(bd) bd.remove();
    if(dr) dr.remove();
  }

  function openDrawer(obj){
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
    b1.onclick=()=>{ try{ navigator.clipboard.writeText(JSON.stringify(obj,null,2)); }catch(e){} };

    const b2=document.createElement("button");
    b2.textContent="Close";
    b2.onclick=closeDrawer;

    btns.appendChild(b1); btns.appendChild(b2);
    dr.appendChild(btns);

    const x=document.createElement("div");
    x.className="x";
    x.textContent="Click outside to close. Copy JSON to attach evidence into ticket.";
    dr.appendChild(x);

    Object.keys(obj||{}).forEach(k=>{
      const kv=document.createElement("div"); kv.className="kv";
      const kk=document.createElement("div"); kk.className="k"; kk.textContent=k;
      const vv=document.createElement("div"); vv.className="v"; vv.textContent=(obj[k]==null?"":String(obj[k]));
      kv.appendChild(kk); kv.appendChild(vv);
      dr.appendChild(kv);
    });

    document.body.appendChild(bd);
    document.body.appendChild(dr);
  }

  function parseRow(tr){
    const table=tr.closest("table");
    if(!table) return {};
    const ths=[...table.querySelectorAll("thead th")].map(x=>(x.innerText||"").trim()||"col");
    const tds=[...tr.querySelectorAll("td")].map(x=>(x.innerText||"").trim());
    const obj={};
    for(let i=0;i<tds.length;i++){
      const key=ths[i] || ("col"+i);
      obj[key]=tds[i];
    }
    // also stash raw row text
    obj.__row_text__ = (tr.innerText||"").trim();
    return obj;
  }

  function chooseBestTable(){
    const tables=[...document.querySelectorAll("table")];
    let best=null, bestScore=0;
    for(const tb of tables){
      const rows=tb.querySelectorAll("tbody tr").length;
      const cols=Math.max(
        tb.querySelectorAll("thead th").length,
        tb.querySelectorAll("tbody tr td").length // rough
      );
      if(rows < 8) continue;
      const score = rows * Math.min(cols, 50);
      if(score > bestScore){
        bestScore = score;
        best = tb;
      }
    }
    return best;
  }

  function wrapSticky(table){
    if(table.closest(".vsp_p481_table_wrap")) return;
    const wrap=document.createElement("div");
    wrap.className="vsp_p481_table_wrap";
    const sc=document.createElement("div");
    sc.className="vsp_p481_table_scroller";
    table.parentNode.insertBefore(wrap, table);
    wrap.appendChild(sc);
    sc.appendChild(table);
  }

  function applyFilter(table, st){
    const rows=[...table.querySelectorAll("tbody tr")];
    let shown=0;
    for(const tr of rows){
      const txt=(tr.innerText||"");
      let ok=true;
      if(st.level){
        ok = ok && txt.toUpperCase().includes(st.level);
      }
      if(st.tool){
        ok = ok && txt.toLowerCase().includes(st.tool.toLowerCase());
      }
      tr.style.display = ok ? "" : "none";
      if(ok) shown++;
    }
    console.log("[P481b] filter", st, "shown", shown);
  }

  function ensureBar(table){
    if(document.getElementById("vsp_p481_bar")) return;

    const bar=document.createElement("div");
    bar.id="vsp_p481_bar";

    const state={level:null, tool:null};

    function mkChip(level){
      const c=document.createElement("span");
      c.className="vsp_p481_chip";
      c.textContent=level;
      c.onclick=()=>{
        if(state.level===level){
          state.level=null; c.classList.remove("on");
        }else{
          [...bar.querySelectorAll('.vsp_p481_chip[data-k="level"]')].forEach(x=>x.classList.remove("on"));
          state.level=level; c.classList.add("on");
        }
        applyFilter(table, state);
      };
      c.dataset.k="level";
      return c;
    }

    LEVELS.forEach(l=>bar.appendChild(mkChip(l)));

    const sep=document.createElement("span");
    sep.className="vsp_p481_sep";
    sep.textContent="|";
    bar.appendChild(sep);

    const inp=document.createElement("input");
    inp.placeholder="Filter tool (e.g. grype, semgrep)...";
    inp.style.cssText="flex:1;min-width:220px;border-radius:12px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.02);color:rgba(255,255,255,0.9);padding:7px 10px;font-size:12px;";
    inp.oninput=()=>{
      state.tool = (inp.value||"").trim() || null;
      applyFilter(table, state);
    };
    bar.appendChild(inp);

    table.parentNode.insertBefore(bar, table);
  }

  function wireRows(table){
    const rows=[...table.querySelectorAll("tbody tr")];
    for(const tr of rows){
      if(tr.dataset.vspP481bWired==="1") continue;
      tr.dataset.vspP481bWired="1";
      tr.classList.add("vsp_p481_row");
      tr.addEventListener("click", ()=>openDrawer(parseRow(tr)));
    }
    document.addEventListener("keydown",(e)=>{ if(e.key==="Escape") closeDrawer(); });
  }

  function run(){
    if(!onDS()) return;
    ensureCss();

    // If already visible from P481, do nothing
    if(document.getElementById("vsp_p481_bar")) {
      console.log("[P481b] bar already present");
      return;
    }

    const tb=chooseBestTable();
    if(!tb){
      console.log("[P481b] no suitable table found yet, retrying...");
      setTimeout(run, 900);
      return;
    }

    ensureBar(tb);
    wrapSticky(tb);
    wireRows(tb);
    console.log("[P481b] datasource fallback applied");
  }

  function boot(){
    if(!onDS()) return;
    // wait a bit for tables to render
    setTimeout(run, 600);
    setTimeout(run, 1500);
    setTimeout(run, 2600);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] patched P481b fallback into vsp_c_common_v1.js")
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

echo "[OK] P481b done. Close tab /c/data_source, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
