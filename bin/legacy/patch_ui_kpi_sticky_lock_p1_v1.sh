#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_sticky_${TS}" && echo "[BACKUP] $F.bak_kpi_sticky_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_KPI_STICKY_LOCK_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# Ensure standalone marker exists
if "VSP_KPI_STANDALONE_FROM_FINDINGS_V2_P1_V1" not in s:
    raise SystemExit("[ERR] standalone block not found; run append patch first")

addon = r'''
/* === VSP_KPI_STICKY_LOCK_P1_V1 ===
   After standalone writes KPI values, prevent other modules from overwriting via _vspSetTextK/_vspSetHTMLK.
*/
(function(){
  if (window.__VSP_KPI_STICKY_LOCKED__) return;
  window.__VSP_KPI_STICKY_LOCKED__ = 1;

  var IDS = ["kpi-overall","kpi-overall-sub","kpi-gate","kpi-gate-sub","kpi-gitleaks","kpi-gitleaks-sub","kpi-codeql","kpi-codeql-sub"];

  function el(id){ try{return document.getElementById(id);}catch(_){return null;} }
  function hasValue(e){
    try{
      var t=(e && (e.textContent||"") || "").trim();
      if(!t) return false;
      var u=t.toUpperCase();
      return (t !== "…" && t !== "—" && u !== "N/A");
    }catch(_){ return false; }
  }
  function stable(id){
    var e=el(id);
    try{ return !!(e && e.getAttribute("data-vsp-kpi-stable")==="1" && hasValue(e)); }catch(_){ return false; }
  }
  function markStable(){
    for (var i=0;i<IDS.length;i++){
      var e=el(IDS[i]);
      try{ if(e) e.setAttribute("data-vsp-kpi-stable","1"); }catch(_){}
    }
  }

  // Wrap setters (if exist)
  var _origText = window._vspSetTextK;
  var _origHTML = window._vspSetHTMLK;

  if (typeof _origText === "function" && !window.__VSP_SET_TEXTK_WRAPPED__){
    window.__VSP_SET_TEXTK_WRAPPED__ = 1;
    window._vspSetTextK = function(id, v){
      try{ if(stable(id)) return false; }catch(_){}
      return _origText(id, v);
    };
  }
  if (typeof _origHTML === "function" && !window.__VSP_SET_HTMLK_WRAPPED__){
    window.__VSP_SET_HTMLK_WRAPPED__ = 1;
    window._vspSetHTMLK = function(id, v){
      try{ if(stable(id)) return false; }catch(_){}
      return _origHTML(id, v);
    };
  }

  // Mark stable periodically (SPA can re-mount)
  try{
    setTimeout(markStable, 200);
    setTimeout(markStable, 800);
    setInterval(markStable, 2000);
  }catch(_){}
})();
'''

s = s + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
