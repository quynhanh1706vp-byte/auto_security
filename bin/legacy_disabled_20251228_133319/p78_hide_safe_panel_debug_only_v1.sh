#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p78_${TS}"
echo "[OK] backup ${F}.bak_p78_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P78_SAFE_PANEL_DEBUG_ONLY_V1"
if marker in s:
    print("[OK] already patched P78")
    raise SystemExit(0)

inject = r"""
/* VSP_P78_SAFE_PANEL_DEBUG_ONLY_V1
 * Hide SAFE panel by default (commercial). Show only when ?debug=1 or localStorage.vsp_safe_show=1.
 */
(function(){
  function hasDebug(){
    try{ return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){ return false; }
  }
  function wantShow(){
    try{ return (localStorage.getItem("vsp_safe_show")==="1"); }catch(e){ return false; }
  }
  function setShow(v){
    try{ localStorage.setItem("vsp_safe_show", v ? "1" : "0"); }catch(e){}
  }
  function findSafeRoot(){
    var nodes = document.querySelectorAll("div,span,b,strong");
    for (var i=0;i<nodes.length;i++){
      var t = (nodes[i].textContent||"").trim();
      if (t.indexOf("VSP Dashboard (SAFE)") >= 0){
        var el = nodes[i];
        for (var k=0;k<10 && el; k++){
          if (el.style && (el.style.position==="fixed" || el.style.position==="absolute")) return el;
          el = el.parentElement;
        }
        el = nodes[i].closest("div");
        if (el) return el;
      }
    }
    return null;
  }
  function apply(){
    var show = hasDebug() || wantShow();
    var root = findSafeRoot();
    if (!root) return;
    root.setAttribute("data-vsp-panel","safe");
    if (!show) root.style.display="none";
    else root.style.display="";
    // If this panel has a "Hide" button, make it persist
    try{
      var btns = root.querySelectorAll("button");
      for (var i=0;i<btns.length;i++){
        var b = btns[i];
        var txt = (b.textContent||"").trim().toLowerCase();
        if (txt==="hide" && !b.getAttribute("data-p78")){
          b.setAttribute("data-p78","1");
          b.addEventListener("click", function(){
            setShow(false);
            try{ root.style.display="none"; }catch(e){}
          }, true);
        }
      }
    }catch(e){}
  }
  function loop(n){
    apply();
    if (n<=0) return;
    setTimeout(function(){ loop(n-1); }, 200);
  }
  if (document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", function(){ loop(25); }, {once:true});
  } else {
    loop(25);
  }
})();
"""
p.write_text(s.rstrip() + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] P78 appended SAFE panel hider (debug-only)")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax FAIL"; exit 2; }
fi

echo "[DONE] P78 applied. Reload (Ctrl+Shift+R). SAFE panel hidden unless ?debug=1"
