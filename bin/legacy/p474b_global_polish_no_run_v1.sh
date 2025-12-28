#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_sidebar_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p474b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p474b_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

# NOTE: pipe must be on THIS line (bash), not inside python
python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path

p = Path("static/js/vsp_c_sidebar_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P474_GLOBAL_POLISH_NO_RUN_V1"
if MARK in s:
    print("[OK] already patched P474")
else:
    add = r"""

/* VSP_P474_GLOBAL_POLISH_NO_RUN_V1 */
(function(){
  function addCss2(){
    if(document.getElementById("vsp_p474_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p474_css";
    st.textContent=`
/* ===== Commercial UI polish (global) ===== */
.vsp_p473_frame{max-width:1440px}
.vsp_p473_frame, #vsp_p473_wrap{min-height:calc(100vh - 10px)}
body{letter-spacing:.1px}
h1,h2,h3{font-weight:800}

/* Unified card */
.vsp_card{
  background:rgba(255,255,255,0.02);
  border:1px solid rgba(255,255,255,0.06);
  border-radius:16px;
  box-shadow:0 10px 30px rgba(0,0,0,0.25);
}

/* Tables */
table{border-collapse:separate;border-spacing:0;width:100%}
th,td{padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.06)}
th{font-size:12px;opacity:.85;text-transform:uppercase;letter-spacing:.7px}
tr:hover td{background:rgba(255,255,255,0.02)}
div[role="row"], .row{border-bottom:1px solid rgba(255,255,255,0.06)}

/* Inputs */
input,select,textarea{
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.9);
  border:1px solid rgba(255,255,255,0.08);
  border-radius:12px;
  padding:10px 12px;
  outline:none;
}
input:focus,select:focus,textarea:focus{
  border-color:rgba(99,179,237,0.40);
  box-shadow:0 0 0 3px rgba(99,179,237,0.14);
}

/* Buttons */
button, .btn, a.btn{
  border-radius:12px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  color:rgba(255,255,255,0.88);
  padding:8px 12px;
}
button:hover, .btn:hover, a.btn:hover{background:rgba(255,255,255,0.06)}
button:disabled{opacity:.5;cursor:not-allowed}

/* Badge */
.vsp_badge{
  display:inline-flex;align-items:center;gap:6px;
  padding:4px 10px;border-radius:999px;
  border:1px solid rgba(255,255,255,0.10);
  background:rgba(255,255,255,0.03);
  font-size:12px;opacity:.92;
}

/* Title bar */
#vsp_p474_titlebar{
  display:flex;align-items:center;justify-content:space-between;
  gap:12px;margin:6px 0 14px;
  padding:12px 14px;
  border-radius:16px;
  border:1px solid rgba(255,255,255,0.06);
  background:rgba(255,255,255,0.02);
}
#vsp_p474_titlebar .t{font-weight:900;font-size:14px;letter-spacing:.3px}
#vsp_p474_titlebar .sub{font-size:12px;opacity:.75;margin-top:2px}
#vsp_p474_titlebar .r{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
`;
    document.head.appendChild(st);
  }

  function inferTitle(){
    const a=document.querySelector("#vsp_side_menu_v1 a.active");
    return a ? (a.textContent||"").trim() : "VSP";
  }

  function injectTitlebar(){
    addCss2();
    const root = document.querySelector(".vsp_p473_frame") || document.getElementById("vsp_p473_wrap") || document.body;
    if(!root) return;
    if(document.getElementById("vsp_p474_titlebar")) return;

    const bar=document.createElement("div");
    bar.id="vsp_p474_titlebar";

    const left=document.createElement("div");
    const t=document.createElement("div"); t.className="t"; t.textContent=inferTitle();
    const sub=document.createElement("div"); sub.className="sub"; sub.textContent=location.pathname;
    left.appendChild(t); left.appendChild(sub);

    const right=document.createElement("div");
    right.className="r";
    const env=document.createElement("span");
    env.className="vsp_badge";
    env.textContent="LOCAL • 127.0.0.1";
    right.appendChild(env);

    bar.appendChild(left);
    bar.appendChild(right);

    if(root === document.body) document.body.insertBefore(bar, document.body.firstChild);
    else root.insertBefore(bar, root.firstChild);
  }

  function boot(){
    try{
      injectTitlebar();
      console && console.log && console.log("[P474] global polish applied");
    }catch(e){
      console && console.warn && console.warn("[P474] err", e);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 50));
  else setTimeout(boot, 50);
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P474 into vsp_c_sidebar_v1.js")
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

echo "[OK] P474b done. Close ALL /c/* tabs, reopen any /c/* then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
