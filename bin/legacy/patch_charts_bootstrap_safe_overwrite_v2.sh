#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_dashboard_charts_bootstrap_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "$JS.bak_overwrite_safe_${TS}"
echo "[BACKUP] $JS.bak_overwrite_safe_${TS}"

cat > "$JS" <<'JSX'
// vsp_dashboard_charts_bootstrap_v1.js (SAFE overwrite)
// - No recursion, no call-stack overflow
// - Init once when both engine + dashboard data are available
// - Retry bounded with setTimeout

(function(){
  if (window.__VSP_CHARTS_BOOT_SAFE_V2) return;
  window.__VSP_CHARTS_BOOT_SAFE_V2 = true;

  var tries = 0;
  var MAX_TRIES = 20;
  var DONE = false;

  function pickEngine(){
    return window.VSP_CHARTS_ENGINE_V3 || window.VSP_CHARTS_ENGINE_V2 || window.VSP_CHARTS_ENGINE || null;
  }
  function pickData(){
    return window.__VSP_DASH_LAST_DATA_V3 || window.__VSP_DASH_LAST_DATA || window.__VSP_DASH_LAST_DATA_ANY || null;
  }

  function attempt(tag){
    if (DONE) return true;
    var eng = pickEngine();
    var data = pickData();
    if (!eng || !eng.initAll || !data) return false;
    try{
      var ok = eng.initAll(data);
      DONE = true;
      console.log('[VSP_CHARTS_BOOT_SAFE_V2] initAll OK via', tag, 'engine=', (eng===window.VSP_CHARTS_ENGINE_V3?'V3':'OTHER'));
      return !!ok;
    }catch(e){
      console.warn('[VSP_CHARTS_BOOT_SAFE_V2] initAll failed', e);
      return false;
    }
  }

  function schedule(){
    if (DONE) return;
    if (tries++ >= MAX_TRIES) {
      console.warn('[VSP_CHARTS_BOOT_SAFE_V2] give up after', MAX_TRIES, 'tries');
      return;
    }
    setTimeout(function(){
      if (attempt('retry#'+tries)) return;
      schedule();
    }, 200);
  }

  window.addEventListener('vsp:charts-ready', function(){
    attempt('charts-ready');
  });

  window.addEventListener('DOMContentLoaded', function(){
    if (!attempt('domcontentloaded')) schedule();
  });

  // immediate best-effort
  if (!attempt('immediate')) schedule();

})();
JSX

echo "[OK] overwritten $JS with SAFE bootstrap"
echo "[NOTE] no service restart needed; just refresh browser"
