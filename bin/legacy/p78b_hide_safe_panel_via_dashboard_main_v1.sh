#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_main_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F (did you create dashboard_main_v1.js?)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p78b_${TS}"
echo "[OK] backup ${F}.bak_p78b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dashboard_main_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P78B_SAFE_HIDE_MAIN_V1"
if marker in s:
    print("[OK] already patched P78B")
    raise SystemExit(0)

inject = r"""
/* VSP_P78B_SAFE_HIDE_MAIN_V1
 * Commercial default: hide "VSP Dashboard (SAFE)" panel unless ?debug=1 or localStorage.vsp_safe_show=1
 * Works even if panel is injected later (MutationObserver).
 */
(function(){
  function hasDebug(){
    try{ return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){ return false; }
  }
  function wantShow(){
    try{ return (localStorage.getItem("vsp_safe_show")==="1"); }catch(e){ return false; }
  }
  function shouldHide(){ return !(hasDebug() || wantShow()); }

  function hideIfSafe(el){
    try{
      if (!el) return;
      // Check the element and a few descendants quickly
      var txt = (el.textContent||"");
      if (txt && txt.indexOf("VSP Dashboard (SAFE)") >= 0){
        // Find a reasonable floating container to hide
        var root = el;
        for (var k=0;k<12 && root; k++){
          if (root.style && (root.style.position==="fixed" || root.style.position==="absolute")) break;
          root = root.parentElement;
        }
        root = root || el;
        root.setAttribute("data-vsp-panel","safe");
        if (shouldHide()) root.style.display = "none";
      }
    }catch(e){}
  }

  function sweep(){
    try{
      if (!shouldHide()) return;
      var nodes = document.querySelectorAll("div,section,aside");
      for (var i=0;i<nodes.length;i++){
        var t = (nodes[i].textContent||"");
        if (t.indexOf("VSP Dashboard (SAFE)") >= 0){
          hideIfSafe(nodes[i]);
        }
      }
    }catch(e){}
  }

  // Initial sweep + watch DOM changes
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", function(){
      sweep();
    }, {once:true});
  } else {
    sweep();
  }

  try{
    var mo = new MutationObserver(function(muts){
      if (!shouldHide()) return;
      for (var i=0;i<muts.length;i++){
        var m = muts[i];
        if (m.addedNodes){
          for (var j=0;j<m.addedNodes.length;j++){
            var n = m.addedNodes[j];
            if (n && n.nodeType===1) hideIfSafe(n);
          }
        }
      }
    });
    mo.observe(document.documentElement || document.body, {childList:true, subtree:true});
  }catch(e){}
})();
"""

p.write_text(s.rstrip() + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] P78B appended SAFE hider into dashboard_main_v1.js")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax FAIL"; exit 2; }
fi

echo "[DONE] P78B applied. Hard refresh: Ctrl+Shift+R"
