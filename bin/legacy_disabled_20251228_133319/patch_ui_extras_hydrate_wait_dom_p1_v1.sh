#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_extras_waitdom_${TS}" && echo "[BACKUP] $F.bak_extras_waitdom_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_EXTRAS_WAIT_DOM_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# Find a good insertion point near the extras hydrate function.
# We'll inject a helper that re-runs hydrate when KPI nodes appear.
m = re.search(r'function\s+hydrate\s*\(\s*\)\s*\{', s)
if not m:
    raise SystemExit("[ERR] cannot find function hydrate(){ in vsp_ui_4tabs_commercial_v1.js")

ins = r'''
  // === VSP_EXTRAS_WAIT_DOM_P1_V1 ===
  function _vspHasKpiNodes(){
    try{
      return !!(document.getElementById("kpi-overall") && document.getElementById("kpi-gate"));
    }catch(_){ return false; }
  }
  function _vspHydrateSoon(){
    try{
      setTimeout(()=>{ try{ hydrate(); }catch(_){ } }, 50);
      setTimeout(()=>{ try{ hydrate(); }catch(_){ } }, 250);
      setTimeout(()=>{ try{ hydrate(); }catch(_){ } }, 800);
      setTimeout(()=>{ try{ hydrate(); }catch(_){ } }, 1600);
    }catch(_){}
  }
  function _vspInstallKpiObserver(){
    try{
      if(window.__VSP_KPI_OBS_INSTALLED__) return;
      window.__VSP_KPI_OBS_INSTALLED__ = 1;

      // 1) quick retry now
      _vspHydrateSoon();

      // 2) observe DOM changes (pane mount / route change)
      const obs = new MutationObserver(()=>{
        if(_vspHasKpiNodes()){
          _vspHydrateSoon();
        }
      });
      obs.observe(document.documentElement || document.body, {subtree:true, childList:true});

      // 3) periodic safety (commercial hardening)
      setInterval(()=>{
        if(_vspHasKpiNodes()) _vspHydrateSoon();
      }, 3000);
    }catch(_){}
  }
'''

# Inject helper right after hydrate() declaration line (after "{")
pos = m.end()
s = s[:pos] + ins + s[pos:]

# Now ensure observer is installed once after boot/hydrate init.
# We try to hook after DOMContentLoaded or end of file; safest: append at end.
tail = r'''
// === VSP_EXTRAS_WAIT_DOM_P1_V1_BOOT ===
try{
  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=>{ try{ _vspInstallKpiObserver(); }catch(_){ } });
  }else{
    _vspInstallKpiObserver();
  }
}catch(_){}
'''
s = s + "\n" + tail + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
