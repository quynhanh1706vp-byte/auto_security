#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_global_kpi_${TS}" && echo "[BACKUP] $F.bak_global_kpi_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_GLOBAL_KPI_GUARDS_P1_V2"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

prefix = r'''/* === VSP_GLOBAL_KPI_GUARDS_P1_V2 ===
   Ensure _vspSetTextK/_vspSetHTMLK exist in GLOBAL scope (file has multiple IIFEs/modules).
*/
var _vspKpiEl = (typeof _vspKpiEl === "function") ? _vspKpiEl : function(id){
  try{ return document.getElementById(id); }catch(_){ return null; }
};
var _vspKpiHasValue = (typeof _vspKpiHasValue === "function") ? _vspKpiHasValue : function(el){
  try{
    var t = (el && (el.textContent||"") || "").trim();
    if(!t) return false;
    var u = t.toUpperCase();
    return (t !== "…" && t !== "—" && u !== "N/A");
  }catch(_){ return false; }
};
var _vspKpiLocked = (typeof _vspKpiLocked === "function") ? _vspKpiLocked : function(id){
  var el=_vspKpiEl(id);
  try{ return !!(el && el.getAttribute("data-vsp-kpi-lock")==="1"); }catch(_){ return false; }
};
var _vspKpiLock = (typeof _vspKpiLock === "function") ? _vspKpiLock : function(id){
  var el=_vspKpiEl(id);
  try{ if(el) el.setAttribute("data-vsp-kpi-lock","1"); }catch(_){}
};
var _vspSetTextK = (typeof _vspSetTextK === "function") ? _vspSetTextK : function(id, v){
  var el=_vspKpiEl(id);
  if(!el) return false;
  if(_vspKpiLocked(id) && _vspKpiHasValue(el)) return false;
  try{
    el.textContent = (v===0) ? "0" : (v ? String(v) : "—");
    return true;
  }catch(_){ return false; }
};
var _vspSetHTMLK = (typeof _vspSetHTMLK === "function") ? _vspSetHTMLK : function(id, html){
  var el=_vspKpiEl(id);
  if(!el) return false;
  if(_vspKpiLocked(id) && _vspKpiHasValue(el)) return false;
  try{
    el.innerHTML = (html===0) ? "0" : (html ? String(html) : "—");
    return true;
  }catch(_){ return false; }
};
/* === END VSP_GLOBAL_KPI_GUARDS_P1_V2 === */
'''

p.write_text(prefix + "\n" + s, encoding="utf-8")
print("[OK] prepended", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
