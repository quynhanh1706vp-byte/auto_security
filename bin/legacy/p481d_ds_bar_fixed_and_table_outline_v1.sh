#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F_DS="static/js/vsp_c_data_source_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p481d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F_DS" ] || { echo "[ERR] missing $F_DS" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F_DS}.bak_p481d_${TS}"
cp -f "$F_DS" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_data_source_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P481D_DS_BAR_FIXED_AND_TABLE_OUTLINE_V1"
if MARK in s:
    print("[OK] already patched P481d")
else:
    s += r"""

/* VSP_P481D_DS_BAR_FIXED_AND_TABLE_OUTLINE_V1 */
(function(){
  if (window.__VSP_P481D__) return;
  window.__VSP_P481D__ = 1;

  const LEVELS=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

  function onDS(){ return location.pathname.includes("/c/data_source"); }

  function ensureCss(){
    if(document.getElementById("vsp_p481d_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p481d_css";
    st.textContent=`
/* fixed bar always visible */
#vsp_p481_bar_fixed{
  position: fixed;
  top: 74px;                /* below top header */
  left: 240px;              /* leave room for sidebar */
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
  #vsp_p481_bar_fixed{ left: 14px; right: 14px; top: 64px; }
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

#vsp_p481_tool_inp{
  flex: 1;
  min-width: 220px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.10);
  background: rgba(255,255,255,0.02);
  color: rgba(255,255,255,0.92);
  padding: 7px 10px;
  font-size: 12px;
}

#vsp_p481_bar_fixed .mini{
  opacity:.72;
  font-size:11px;
  margin-left:auto;
  display:flex;
  gap:8px;
  align-items:center;
  flex-wrap:wrap;
}
#vsp_p481_bar_fixed button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:6px 10px;
  font-size:12px;
  cursor:pointer;
}
#vsp_p481_bar_fixed button:hover{ background:rgba(255,255,255,0.06); }

/* highlight the selected table */
.vsp_p481_target_table{
  outline: 2px solid rgba(99,179,237,0.45) !important;
  outline-offset: 3px !important;
  border-radius: 10px;
}
.vsp_p481_target_wrap{
  position: relative;
}
.vsp_p481_target_tag{
  position:absolute;
  top:-10px; left:12px;
  z-index: 3;
  border-radius: 999px;
  border: 1px solid rgba(99,179,237,0.35);
  background: rgba(99,179,237,0.12);
  color:#fff;
  padding: 4px 8px;
  font-size: 11px;
  backdrop-filter: blur(6px);
}

/* small padding so content not hidden behind fixed bar */
body.vsp_p481d_pad_top{
  padding-top: 58px;
}
`;
    document.head.appendChild(st);
  }

  function ensureTopPad(){
    document.body.classList.add("vsp_p481d_pad_top");
  }

  function chooseBestTable(){
    const tables=[...document.querySelectorAll("table")];
    let best=null, bestScore=0;
    for(const tb of tables){
      const rows=tb.querySelectorAll("tbody tr").length;
      const cols=Math.max(tb.querySelectorAll("thead th").length, 1);
      if(rows < 8) continue;
      const score = rows * Math.min(cols, 50);
      if(score > bestScore){ bestScore=score; best=tb; }
    }
    return best;
  }

  function clearOldMark(){
    document.querySelectorAll(".vsp_p481_target_table").forEach(x=>x.classList.remove("vsp_p481_target_table"));
    document.querySelectorAll(".vsp_p481_target_tag").forEach(x=>x.remove());
    document.querySelectorAll(".vsp_p481_target_wrap").forEach(x=>x.classList.remove("vsp_p481_target_wrap"));
  }

  function markTable(tb){
    try{
      clearOldMark();
      tb.classList.add("vsp_p481_target_table");
      const parent = tb.parentElement || tb;
      parent.classList.add("vsp_p481_target_wrap");
      const tag=document.createElement("div");
      tag.className="vsp_p481_target_tag";
      tag.textContent="TARGET TABLE (P481d)";
      parent.style.position = parent.style.position || "relative";
      parent.appendChild(tag);
    }catch(e){}
  }

  function applyFilter(tb, st){
    const rows=[...tb.querySelectorAll("tbody tr")];
    let shown=0;
    for(const tr of rows){
      const txt=(tr.innerText||"");
      let ok=true;
      if(st.level) ok = ok && txt.toUpperCase().includes(st.level);
      if(st.tool) ok = ok && txt.toLowerCase().includes(st.tool.toLowerCase());
      tr.style.display = ok ? "" : "none";
      if(ok) shown++;
    }
    const lab=document.getElementById("vsp_p481_count");
    if(lab) lab.textContent = `shown=${shown}`;
  }

  function ensureBar(tb){
    if(document.getElementById("vsp_p481_bar_fixed")) return;

    const bar=document.createElement("div");
    bar.id="vsp_p481_bar_fixed";

    const st={level:null, tool:null};

    function mkChip(lv){
      const c=document.createElement("span");
      c.className="vsp_p481_chip";
      c.textContent=lv;
      c.onclick=()=>{
        if(st.level===lv){
          st.level=null; c.classList.remove("on");
        }else{
          [...bar.querySelectorAll('.vsp_p481_chip[data-k="level"]')].forEach(x=>x.classList.remove("on"));
          st.level=lv; c.classList.add("on");
        }
        applyFilter(tb, st);
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
    inp.id="vsp_p481_tool_inp";
    inp.placeholder="Filter tool (e.g. grype, semgrep)...";
    inp.oninput=()=>{ st.tool=(inp.value||"").trim()||null; applyFilter(tb, st); };
    bar.appendChild(inp);

    const mini=document.createElement("div");
    mini.className="mini";

    const cnt=document.createElement("span");
    cnt.id="vsp_p481_count";
    cnt.textContent="shown=?";
    mini.appendChild(cnt);

    const bScroll=document.createElement("button");
    bScroll.textContent="Scroll to table";
    bScroll.onclick=()=>{ try{ tb.scrollIntoView({behavior:"smooth", block:"center"}); }catch(e){} };
    mini.appendChild(bScroll);

    const bClear=document.createElement("button");
    bClear.textContent="Clear";
    bClear.onclick=()=>{
      st.level=null; st.tool=null;
      [...bar.querySelectorAll('.vsp_p481_chip.on')].forEach(x=>x.classList.remove("on"));
      inp.value="";
      applyFilter(tb, st);
    };
    mini.appendChild(bClear);

    bar.appendChild(mini);

    document.body.appendChild(bar);

    // initial count
    applyFilter(tb, st);
  }

  function run(){
    if(!onDS()) return;
    ensureCss();
    ensureTopPad();

    const tb=chooseBestTable();
    if(!tb){
      console.log("[P481d] no suitable table yet, retry...");
      setTimeout(run, 900);
      return;
    }

    markTable(tb);
    ensureBar(tb);

    console.log("[P481d] fixed bar + table outline applied");
  }

  function boot(){
    if(!onDS()) return;
    setTimeout(run, 700);
    setTimeout(run, 1600);
    setTimeout(run, 2600);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] patched P481d into vsp_c_data_source_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F_DS" >/dev/null 2>&1 || { echo "[ERR] node check failed: $F_DS" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P481d done. Close tab /c/data_source, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
