#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runtime_error_overlay_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p77b_${TS}"
echo "[OK] backup ${F}.bak_p77b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runtime_error_overlay_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P77B_P64_FORCE_HIDE_V1"
if marker in s:
    print("[OK] already patched P77B")
    raise SystemExit(0)

inject = r"""
/* VSP_P77B_P64_FORCE_HIDE_V1
 * Default: hide overlay unless ?debug=1 OR localStorage.vsp_p64_show=1
 * Persist hide/show.
 */
(function(){
  function hasDebug(){
    try{ return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){ return false; }
  }
  function wantShow(){
    try{ return (localStorage.getItem("vsp_p64_show") === "1"); }catch(e){ return false; }
  }
  function setShow(v){
    try{ localStorage.setItem("vsp_p64_show", v ? "1" : "0"); }catch(e){}
  }

  function findOverlayRoot(){
    // Find any node containing the exact label
    var nodes = document.querySelectorAll("div,span,b,strong");
    for (var i=0;i<nodes.length;i++){
      var t = (nodes[i].textContent||"").trim();
      if (t.indexOf("VSP Runtime Overlay") >= 0 && t.indexOf("(P64)") >= 0){
        // climb up to a reasonable root (floating panel)
        var el = nodes[i];
        for (var k=0;k<8 && el; k++){
          if (el.style && (el.style.position === "fixed" || el.style.position === "absolute")) return el;
          el = el.parentElement;
        }
        // fallback: nearest div container
        el = nodes[i].closest("div");
        if (el) return el;
      }
    }
    return null;
  }

  function apply(){
    var debug = hasDebug();
    var show = debug || wantShow();
    var root = findOverlayRoot();
    if (!root) return;

    // mark
    root.setAttribute("data-vsp-overlay","p64");

    // Persist behavior: if not show => hide
    if (!show){
      root.style.display = "none";
    } else {
      root.style.display = "";
    }

    // Patch built-in Hide/Clear buttons to persist show/hide
    try{
      var btns = root.querySelectorAll("button");
      for (var i=0;i<btns.length;i++){
        var b = btns[i];
        var txt = (b.textContent||"").trim().toLowerCase();
        if (txt === "hide"){
          if (!b.getAttribute("data-p77b")){
            b.setAttribute("data-p77b","1");
            b.addEventListener("click", function(){
              setShow(false);
              try{ root.style.display="none"; }catch(e){}
            }, true);
          }
        }
        if (txt === "clear"){
          // no-op persist
        }
      }
    }catch(e){}
  }

  // Run multiple times to catch late DOM injection
  function loop(n){
    apply();
    if (n<=0) return;
    setTimeout(function(){ loop(n-1); }, 200);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function(){ loop(25); }, {once:true});
  } else {
    loop(25);
  }
})();
"""
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] P77B appended brute-force overlay hider + persist toggle")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax FAIL"; exit 2; }
fi

echo "[DONE] P77B applied. Reload (Ctrl+Shift+R). Overlay should be hidden unless ?debug=1"
