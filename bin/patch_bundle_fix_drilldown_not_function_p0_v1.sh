#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_fix_drilldown_nf_${TS}"
echo "[BACKUP] $F.bak_fix_drilldown_nf_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DRILLDOWN_NOT_FUNCTION_GUARD_P0_V1"
if MARK in s:
    print("[OK] guard already present")
    raise SystemExit(0)

shim = r'''
/* %s: guard drilldown artifacts hook to avoid "not a function" */
(function(){
  'use strict';
  try{
    var k='VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2';
    var v=window[k];
    if(typeof v==='function') return;

    window[k]=function(){
      try{
        // try to delegate if previous value is an object with init/install
        if(v && typeof v.install==='function') return v.install.apply(v, arguments);
        if(v && typeof v.init==='function') return v.init.apply(v, arguments);
        if(v && typeof v.run==='function') return v.run.apply(v, arguments);
        console.warn('[DRILLDOWN_GUARD] '+k+' was not function, wrapped. prev=', v);
      }catch(e){
        console.warn('[DRILLDOWN_GUARD] inner err', e);
      }
    };

    console.warn('[DRILLDOWN_GUARD] patched '+k+' type=', typeof window[k], 'prev_type=', typeof v);
  }catch(e){
    console.warn('[DRILLDOWN_GUARD] outer err', e);
  }
})();
''' % MARK

# append at end to override late
s = s.rstrip() + "\n\n" + shim + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended guard:", MARK)
PY

echo "== node --check =="
node --check "$F"

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R, then check Console: no more 'not a function' at :3050"
