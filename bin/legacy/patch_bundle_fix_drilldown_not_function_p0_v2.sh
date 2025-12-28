#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_fix_drilldown_nf_v2_${TS}"
echo "[BACKUP] $F.bak_fix_drilldown_nf_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

old="VSP_DRILLDOWN_NOT_FUNCTION_GUARD_P0_V1"
new="VSP_DRILLDOWN_NOT_FUNCTION_GUARD_P0_V2"

# replace old guard block if exists
pat = re.compile(r"/\*\s*%s:.*?\*/\s*\(function\(\)\{\s*'use strict';.*?\}\)\(\);\s*" % re.escape(old),
                 re.S)
if pat.search(s):
    s = pat.sub("", s, count=1)

shim = r'''
/* %s: guard + SYNC var/window to avoid "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...) is not a function" */
(function(){
  'use strict';
  try{
    var k='VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2';

    // capture both current sources
    var wv = window[k];
    var lv;
    try{ lv = (typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'undefined') ? VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : undefined; }catch(_){ lv = undefined; }

    // choose "best" candidate
    var v = (typeof wv !== 'undefined') ? wv : lv;

    // make callable wrapper
    function makeCallable(prev){
      if(typeof prev === 'function') return prev;
      return function(){
        try{
          if(prev && typeof prev.install==='function') return prev.install.apply(prev, arguments);
          if(prev && typeof prev.init==='function') return prev.init.apply(prev, arguments);
          if(prev && typeof prev.run==='function') return prev.run.apply(prev, arguments);
          console.warn('[DRILLDOWN_GUARD] '+k+' wrapped (prev not callable). prev=', prev);
        }catch(e){
          console.warn('[DRILLDOWN_GUARD] inner err', e);
        }
      };
    }

    var fn = makeCallable(v);

    // IMPORTANT: sync BOTH window and the var
    window[k] = fn;
    try{ VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = fn; }catch(_){}

    // also keep window/var aligned if later code overwrites window[k]
    try{
      Object.defineProperty(window, k, {
        configurable: true,
        get: function(){ return fn; },
        set: function(nv){
          fn = makeCallable(nv);
          try{ VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = fn; }catch(_){}
        }
      });
    }catch(_){}

    console.warn('[DRILLDOWN_GUARD] installed', k, 'type=', typeof window[k]);
  }catch(e){
    console.warn('[DRILLDOWN_GUARD] outer err', e);
  }
})();
''' % new

# append at end (late override)
s = s.rstrip() + "\n\n" + shim + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected", new)
PY

echo "== node --check =="
node --check "$F"

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R, check Console: MUST be no more '...is not a function' for drilldown."
