#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F_RUNS="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F_RUNS" ] || { echo "[ERR] missing $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F_RUNS}.bak_p482_${TS}"
cp -f "$F_RUNS" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P482_RUNS_TOOLBAR_SORT_FILTER_NO_RUN_V1"
if MARK in s:
    print("[OK] already patched P482")
else:
    s += r"""

/* VSP_P482_RUNS_TOOLBAR_SORT_FILTER_NO_RUN_V1 */
(function(){
  if (window.__VSP_P482__) return;
  window.__VSP_P482__ = 1;

  function onRuns(){ return location.pathname.includes("/c/runs"); }

  function ensureCss(){
    if(document.getElementById("vsp_p482_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p482_css";
    st.textContent=`
/* fixed toolbar for runs */
#vsp_p482_bar{
  position: fixed;
  top: 74px;
  left: 240px;
  right: 20px;
  z-index: 9999;
  border-radius: 14px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(12,16,24,0.92);
  backdrop-filter: blur(10px);
  padding: 10px 10px;
  display:flex;
  gap: 8px;
  flex-wrap: wrap;
  align-items: center;
  box-shadow: 0 10px 30px rgba(0,0,0,0.35);
}
@media (max-width: 980px){
  #vsp_p482_bar{ left: 14px; right: 14px; top: 64px; }
}
#vsp_p482_q{
  flex: 1;
  min-width: 260px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.02);
  color: rgba(255,255,255,0.92);
  padding: 7px 10px;
  font-size: 12px;
}
#vsp_p482_sort{
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.02);
  color: rgba(255,255,255,0.90);
  padding: 7px 10px;
  font-size: 12px;
}
.vsp_p482_chip{
  border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.86);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
  user-select:none;
}
.vsp_p482_chip.on{
  border-color:rgba(99,179,237,0.35);
  background:rgba(99,179,237,0.12);
  color:#fff;
}
#vsp_p482_bar .mini{
  margin-left:auto;
  display:flex;
  gap:8px;
  align-items:center;
  flex-wrap:wrap;
  font-size:11px;
  opacity:.78;
}
#vsp_p482_bar button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
}
#vsp_p482_bar button:hover{ background:rgba(255,255,255,0.06); }

/* sticky header for the chosen runs table */
.vsp_p482_table thead th{
  position: sticky;
  top: 0;
  z-index: 2;
  background: rgba(10,14,22,0.96);
  backdrop-filter: blur(8px);
}

/* avoid toolbar overlap */
body.vsp_p482_pad_top{
  padding-top: 58px;
}
`;
    document.head.appendChild(st);
  }

  function chooseRunsTable(){
    const tables=[...document.querySelectorAll("table")];
    let best=null, bestScore=0;

    for(const tb of tables){
      const rows=tb.querySelectorAll("tbody tr").length;
      if(rows < 8) continue;
      const head=(tb.querySelector("thead")?.innerText||"").toLowerCase();
      const score = rows + (head.includes("rid") ? 50 : 0) + (head.includes("status") ? 10 : 0);
      if(score > bestScore){ bestScore=score; best=tb; }
    }
    return best;
  }

  function findColIndex(tb, key){
    const ths=[...tb.querySelectorAll("thead th")];
    for(let i=0;i<ths.length;i++){
      const t=(ths[i].innerText||"").toLowerCase();
      if(t.includes(key)) return i;
    }
    return -1;
  }

  function getCellText(tr, idx){
    const tds=[...tr.querySelectorAll("td")];
    if(idx < 0 || idx >= tds.length) return "";
    return (tds[idx].innerText||"").trim();
  }

  function parseDate(s){
    // try "YYYY-MM-DD HH:MM" first
    const m = s.match(/(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
    if(m){
      const y=int(m[1]); const mo=int(m[2]); const d=int(m[3]); const h=int(m[4]); const mi=int(m[5]);
      return new Date(y,mo-1,d,h,mi,0).getTime();
    }
    // fallback Date.parse
    const t = Date.parse(s);
    return isNaN(t) ? 0 : t;
    function int(x){ try{return parseInt(x,10)}catch(e){return 0} }
  }

  function applyFilterAndSort(tb, st){
    const ridIdx = findColIndex(tb, "rid");
    const dateIdx = findColIndex(tb, "date");
    const statusIdx = findColIndex(tb, "status");

    const rows=[...tb.querySelectorAll("tbody tr")];
    const q=(st.q||"").trim().toLowerCase();
    const wantStatus=(st.status||"ALL").toUpperCase();

    // filter
    let shown=0;
    const kept=[];
    for(const tr of rows){
      const rid = getCellText(tr, ridIdx);
      const date = getCellText(tr, dateIdx);
      const status = getCellText(tr, statusIdx) || "UNKNOWN";
      const blob=(rid+" "+date+" "+status+" "+(tr.innerText||"")).toLowerCase();

      let ok=true;
      if(q) ok = ok && blob.includes(q);
      if(wantStatus !== "ALL"){
        ok = ok && (status.toUpperCase().includes(wantStatus));
      }
      tr.style.display = ok ? "" : "none";
      if(ok){
        shown++;
        kept.append(tr);
      }
    }

    // sort (only visible rows)
    const mode=st.sort||"DATE_DESC";
    kept.sort((a,b)=>{
      const ra=getCellText(a,ridIdx), rb=getCellText(b,ridIdx);
      const da=parseDate(getCellText(a,dateIdx)), db=parseDate(getCellText(b,dateIdx));
      if(mode==="RID_ASC") return ra.localeCompare(rb);
      if(mode==="RID_DESC") return rb.localeCompare(ra);
      if(mode==="DATE_ASC") return da-db;
      return db-da; // DATE_DESC
    });

    const tbody=tb.querySelector("tbody");
    if(tbody){
      for(const tr of kept){ tbody.appendChild(tr); }
    }

    const lab=document.getElementById("vsp_p482_count");
    if(lab) lab.textContent = `shown=${shown}/${rows.length}`;
  }

  function ensureBar(tb){
    if(document.getElementById("vsp_p482_bar")) return;

    document.body.classList.add("vsp_p482_pad_top");
    tb.classList.add("vsp_p482_table");

    const st={ q:"", status:"ALL", sort:"DATE_DESC" };

    const bar=document.createElement("div");
    bar.id="vsp_p482_bar";

    function mkChip(name){
      const c=document.createElement("span");
      c.className="vsp_p482_chip";
      c.textContent=name;
      c.onclick=()=>{
        [...bar.querySelectorAll('.vsp_p482_chip[data-k="status"]')].forEach(x=>x.classList.remove("on"));
        c.classList.add("on");
        st.status=name;
        applyFilterAndSort(tb, st);
      };
      c.dataset.k="status";
      return c;
    }

    // status chips
    const chips=["ALL","OK","WARN","FAIL","UNKNOWN"];
    for(const x of chips){
      const c=mkChip(x);
      if(x==="ALL") c.classList.add("on");
      bar.appendChild(c);
    }

    // search
    const q=document.createElement("input");
    q.id="vsp_p482_q";
    q.placeholder="Search RID / status / anything…";
    q.oninput=()=>{ st.q=q.value||""; applyFilterAndSort(tb, st); };
    bar.appendChild(q);

    // sort
    const sel=document.createElement("select");
    sel.id="vsp_p482_sort";
    const opts=[
      ["DATE_DESC","Date ↓ (newest)"],
      ["DATE_ASC","Date ↑ (oldest)"],
      ["RID_DESC","RID ↓"],
      ["RID_ASC","RID ↑"],
    ];
    for(const [v,t] of opts){
      const o=document.createElement("option");
      o.value=v; o.textContent=t;
      sel.appendChild(o);
    }
    sel.value=st.sort;
    sel.onchange=()=>{ st.sort=sel.value; applyFilterAndSort(tb, st); };
    bar.appendChild(sel);

    // right mini
    const mini=document.createElement("div");
    mini.className="mini";

    const cnt=document.createElement("span");
    cnt.id="vsp_p482_count";
    cnt.textContent="shown=?";
    mini.appendChild(cnt);

    const bTop=document.createElement("button");
    bTop.textContent="Top";
    bTop.onclick=()=>{ window.scrollTo({top:0, behavior:"smooth"}); };
    mini.appendChild(bTop);

    const bClear=document.createElement("button");
    bClear.textContent="Clear";
    bClear.onclick=()=>{
      st.q=""; st.status="ALL"; st.sort="DATE_DESC";
      q.value=""; sel.value=st.sort;
      [...bar.querySelectorAll('.vsp_p482_chip.on')].forEach(x=>x.classList.remove("on"));
      [...bar.querySelectorAll('.vsp_p482_chip[data-k="status"]')].find(x=>x.textContent==="ALL")?.classList.add("on");
      applyFilterAndSort(tb, st);
    };
    mini.appendChild(bClear);

    bar.appendChild(mini);

    document.body.appendChild(bar);
    applyFilterAndSort(tb, st);
    console.log("[P482] runs toolbar ready");
  }

  function boot(){
    if(!onRuns()) return;
    ensureCss();

    const tb=chooseRunsTable();
    if(!tb){
      console.log("[P482] no runs table yet, retry...");
      setTimeout(boot, 900);
      return;
    }
    ensureBar(tb);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 700));
  else setTimeout(boot, 700);
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] patched P482 into vsp_c_runs_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F_RUNS" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F_RUNS" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P482 done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
