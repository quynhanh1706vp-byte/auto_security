#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_sidebar_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p478_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p478_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
p=Path("static/js/vsp_c_sidebar_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P478_DEDUPE_INNER_NAV_ALL_TABS_V1"
if MARK in s:
    print("[OK] already patched P478")
else:
    add = r"""

/* VSP_P478_DEDUPE_INNER_NAV_ALL_TABS_V1 */
(function(){
  if (window.__VSP_P478__) return;
  window.__VSP_P478__ = 1;

  const TABN = ["Dashboard","Runs & Reports","Data Source","Settings","Rule Overrides"]
    .map(s=>s.toLowerCase());

  function ensureCss(){
    if(document.getElementById("vsp_p478_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p478_css";
    st.textContent=`
/* hide duplicate inner nav bars (best-effort) */
.vsp_p478_hide_dupnav{display:none!important}

/* slightly better top spacing inside frame */
.vsp_p473_frame{padding-top:14px}
`;
    document.head.appendChild(st);
  }

  function looksLikeDupNav(el){
    try{
      if(!el || el.id==="vsp_side_menu_v1") return false;
      const h = el.getBoundingClientRect ? el.getBoundingClientRect().height : 999;
      if(h > 140) return false; // nav row usually short
      const btns = el.querySelectorAll ? el.querySelectorAll("a,button") : [];
      if(btns.length < 3) return false;

      const txt = (el.innerText || "").toLowerCase();
      let hit = 0;
      for(const n of TABN){ if(txt.includes(n)) hit++; }
      return hit >= 3; // strong signal it's the 5-tab strip
    }catch(e){
      return false;
    }
  }

  function hideDuplicateNavBars(){
    // scan likely containers; hide the first strong match
    const nodes = Array.from(document.querySelectorAll("nav,header,section,div"));
    let hidden = 0;
    for(const el of nodes){
      if(hidden >= 2) break;
      if(looksLikeDupNav(el)){
        el.classList.add("vsp_p478_hide_dupnav");
        hidden++;
      }
    }
    if(hidden){
      console && console.log && console.log("[P478] hidden dup nav bars:", hidden);
    } else {
      console && console.log && console.log("[P478] no dup nav found");
    }
  }

  function boot(){
    try{
      ensureCss();
      setTimeout(hideDuplicateNavBars, 250);
      setTimeout(hideDuplicateNavBars, 900); // second pass after async render
    }catch(e){
      console && console.warn && console.warn("[P478] err", e);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P478 into vsp_c_sidebar_v1.js")
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

echo "[OK] P478 done. Close ALL /c/* tabs, reopen /c/dashboard then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
