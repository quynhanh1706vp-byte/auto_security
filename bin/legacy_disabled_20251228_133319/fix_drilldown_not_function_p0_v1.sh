#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) write drilldown symbol lock JS =="
JS="static/js/vsp_drilldown_symbol_lock_v1.js"
mkdir -p static/js
cp -f "$JS" "$JS.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* VSP_DRILLDOWN_SYMBOL_LOCK_V1: make sure VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 is ALWAYS a function */
(function(){
  'use strict';

  function stub(){
    try{ console.info("[VSP][DD] stub invoked"); }catch(_){}
    return {open:function(){},show:function(){},close:function(){},destroy:function(){}};
  }

  function lock(){
    try{
      if (typeof window === "undefined") return;

      // keep last known good real impl
      if (typeof window.__vsp_dd_real !== "function") window.__vsp_dd_real = null;

      function getFn(){
        return (typeof window.__vsp_dd_real === "function") ? window.__vsp_dd_real : stub;
      }

      // If property can be defined, lock it
      try{
        Object.defineProperty(window, "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2", {
          configurable: false,
          enumerable: true,
          get: function(){ return getFn(); },
          set: function(v){
            if (typeof v === "function") {
              window.__vsp_dd_real = v;
              try{ console.info("[VSP][DD] accepted real drilldown impl"); }catch(_){}
            } else {
              try{ console.warn("[VSP][DD] blocked non-function overwrite:", v); }catch(_){}
            }
          }
        });
        // normalize existing value (if it was non-function)
        if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
          window.__vsp_dd_real = null;
        }
      }catch(e){
        // Fallback if defineProperty fails: force-correct periodically
        try{ console.warn("[VSP][DD] defineProperty failed, fallback ticker", e); }catch(_){}
        try{
          if (!window.__vsp_dd_fix_timer) {
            window.__vsp_dd_fix_timer = setInterval(function(){
              try{
                if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
                  window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = stub;
                }
              }catch(_){}
            }, 400);
          }
        }catch(_){}
      }
    }catch(_){}
  }

  // early + late lock
  lock();
  try{
    window.addEventListener("DOMContentLoaded", lock, {once:true});
    window.addEventListener("load", lock, {once:true});
  }catch(_){}
})();
JS

node --check "$JS" >/dev/null && echo "[OK] node --check: $JS"

echo "== (2) inject lock JS into template (very early) =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_ddlock_${TS}" && echo "[BACKUP] $TPL.bak_ddlock_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

tpl=Path("templates/vsp_dashboard_2025.html")
s=tpl.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_drilldown_symbol_lock_v1.js?v=%d"></script>\n' % int(time.time())

if "vsp_drilldown_symbol_lock_v1.js" in s:
    print("[OK] lock tag already present")
else:
    # put as early as possible: right after <head> or after hash_normalize if exists
    if "<head" in s:
        m=re.search(r'(?is)<head[^>]*>\s*', s)
        if m:
            i=m.end()
            s = s[:i] + "\n  " + tag + s[i:]
        else:
            s = tag + s
    else:
        s = tag + s

    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected lock tag into template")
PY

echo "== (3) restart 8910 (NO restore) =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "== (4) quick verify tag in HTML =="
curl -sS http://127.0.0.1:8910/vsp4 | grep -n "vsp_drilldown_symbol_lock_v1.js" | head -n 3 || true
echo "[NEXT] Ctrl+Shift+R rồi mở lại:"
echo "  http://127.0.0.1:8910/vsp4/#dashboard"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
