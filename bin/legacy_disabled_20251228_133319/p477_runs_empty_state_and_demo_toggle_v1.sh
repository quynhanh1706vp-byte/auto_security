#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p477_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p477_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path

p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P477_RUNS_EMPTY_STATE_DEMO_V1"
if MARK in s:
    print("[OK] already patched P477")
else:
    add=r"""

/* VSP_P477_RUNS_EMPTY_STATE_DEMO_V1 */
(function(){
  // local-only demo switch: set localStorage.VSP_DEMO_RUNS="1"
  function demoItems(){
    const now = Date.now();
    return [
      { rid:"RUN_DEMO_001", ts: now-3600_000, target:"local/demo", status:"PASS", tools:"8/8", sev:{CRITICAL:0,HIGH:1,MEDIUM:3,LOW:7} },
      { rid:"RUN_DEMO_002", ts: now-7200_000, target:"local/demo", status:"DEGRADED", tools:"6/8", sev:{CRITICAL:0,HIGH:0,MEDIUM:2,LOW:5} },
    ];
  }

  function ensureEmptyCardCss(){
    if(document.getElementById("vsp_p477_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p477_css";
    st.textContent=`
#vsp_runs_empty_v1{
  margin:14px 0;
  padding:16px 16px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_runs_empty_v1 .t{font-weight:900;font-size:14px;letter-spacing:.2px}
#vsp_runs_empty_v1 .d{opacity:.8;margin-top:6px;line-height:1.5}
#vsp_runs_empty_v1 .a{display:flex;gap:10px;flex-wrap:wrap;margin-top:12px}
#vsp_runs_empty_v1 button{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:8px 12px;
}
#vsp_runs_empty_v1 button:hover{background:rgba(255,255,255,0.06)}
`;
    document.head.appendChild(st);
  }

  function insertEmptyCard(){
    ensureEmptyCardCss();
    if(document.getElementById("vsp_runs_empty_v1")) return;

    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;

    const card=document.createElement("div");
    card.id="vsp_runs_empty_v1";
    const t=document.createElement("div");
    t.className="t";
    t.textContent="No runs found (yet)";
    const d=document.createElement("div");
    d.className="d";
    d.innerHTML="This environment has no run history.<br/>For demo, you can enable <b>sample runs</b> locally (no backend change).";
    const a=document.createElement("div");
    a.className="a";

    const b1=document.createElement("button");
    b1.textContent="Enable sample runs (local)";
    b1.onclick=()=>{
      localStorage.setItem("VSP_DEMO_RUNS","1");
      location.reload();
    };

    const b2=document.createElement("button");
    b2.textContent="Disable sample runs";
    b2.onclick=()=>{
      localStorage.removeItem("VSP_DEMO_RUNS");
      location.reload();
    };

    a.appendChild(b1);
    a.appendChild(b2);
    card.appendChild(t);
    card.appendChild(d);
    card.appendChild(a);

    // insert after titlebar if exists
    const tb=document.getElementById("vsp_p474_titlebar");
    if(tb && tb.parentNode){
      tb.parentNode.insertBefore(card, tb.nextSibling);
    }else{
      root.insertBefore(card, root.firstChild);
    }
  }

  // Hook: if page fetches runs and gets empty list, show empty card.
  // Also: if demo flag on, monkeypatch fetch(/api/vsp/runs_v3...) to return sample.
  const DEMO = (localStorage.getItem("VSP_DEMO_RUNS")==="1");

  const _fetch = window.fetch;
  window.fetch = async function(input, init){
    try{
      const url = (typeof input==="string") ? input : (input && input.url) ? input.url : "";
      if(DEMO && url.includes("/api/vsp/runs_v3")){
        const payload = { ver:"demo", items: demoItems() };
        return new Response(JSON.stringify(payload), { status:200, headers:{ "Content-Type":"application/json" } });
      }
    }catch(e){}
    return _fetch.apply(this, arguments);
  };

  function boot(){
    // If demo enabled, show an info badge
    try{
      if(DEMO){
        console && console.log && console.log("[P477] DEMO_RUNS enabled");
      }
      // Delay: allow normal render first, then decide if empty
      setTimeout(()=>{
        try{
          // Heuristic: if table/list container has no rows
          const hasAnyText = document.body && document.body.innerText ? document.body.innerText.includes("RUN_") || document.body.innerText.includes("VSP_CI_") : False;
          // fallback: if known containers exist but empty, show card
          const maybeEmpty = !hasAnyText;
          if(maybeEmpty) insertEmptyCard();
        }catch(e){ insertEmptyCard(); }
      }, 800);
    }catch(e){}
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P477 into vsp_c_runs_v1.js")
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

echo "[OK] P477 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
