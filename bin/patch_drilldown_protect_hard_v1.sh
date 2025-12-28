#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

L="static/js/vsp_ui_loader_route_v1.js"
D="static/js/vsp_dashboard_enhance_v1.js"

[ -f "$L" ] || { echo "[ERR] missing $L"; exit 2; }
[ -f "$D" ] || { echo "[ERR] missing $D"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$L" "$L.bak_protect_${TS}" && echo "[BACKUP] $L.bak_protect_${TS}"
cp -f "$D" "$D.bak_protect_${TS}" && echo "[BACKUP] $D.bak_protect_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

def inject_protect_loader(path: Path):
    s = path.read_text(encoding="utf-8", errors="ignore")
    if "VSP_DRILLDOWN_PROTECT_HARD_V1" not in s:
        marker = "window.__VSP_UI_ROUTE_LOADER_V1 = 1;"
        if marker not in s:
            raise SystemExit("[ERR] cannot find loader marker")
        block = r'''
  // VSP_DRILLDOWN_PROTECT_HARD_V1: keep drilldown symbols always callable even if patches overwrite them
  (function(){
    try{
      function protect(name){
        let fn = (typeof window[name] === 'function') ? window[name] : function(){ return false; };
        Object.defineProperty(window, name, {
          configurable: true,
          enumerable: true,
          get(){ return fn; },
          set(v){
            if (typeof v === 'function') fn = v;
            else {
              try{ console.warn('[VSP_PROTECT] ignore non-function overwrite for', name, typeof v); }catch(_){}
            }
          }
        });
      }
      protect('VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2');
      protect('VSP_DASH_DRILLDOWN_ARTIFACTS_P0_V1');
    }catch(_){}
  })();
'''
        s = s.replace(marker, marker + "\n" + block)

    # Guard direct calls in loader (if any)
    guard_call = r"((typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==='function')?window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:(function(){return false;}))("
    if "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" in s and "typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" not in s:
        s = s.replace("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(", guard_call)

    path.write_text(s, encoding="utf-8")

def guard_calls_dashboard(path: Path):
    s = path.read_text(encoding="utf-8", errors="ignore")

    # Idempotent marker
    if "VSP_DRILLDOWN_CALL_GUARD_V1" not in s:
        s = s.replace("'use strict';", "'use strict';\n  // VSP_DRILLDOWN_CALL_GUARD_V1\n", 1)

    guard_call = r"((typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==='function')?window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:(function(){return false;}))("
    if "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" in s and "typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" not in s:
        s = s.replace("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(", guard_call)

    path.write_text(s, encoding="utf-8")

inject_protect_loader(Path("static/js/vsp_ui_loader_route_v1.js"))
guard_calls_dashboard(Path("static/js/vsp_dashboard_enhance_v1.js"))
print("[OK] patched loader + dashboard drilldown protection/guards")
PY

node --check "$L" >/dev/null && echo "[OK] node --check loader OK"
node --check "$D" >/dev/null && echo "[OK] node --check dashboard OK"

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "[NEXT] Ctrl+Shift+R; DevTools: bỏ tick Preserve log để nhìn lỗi mới."
