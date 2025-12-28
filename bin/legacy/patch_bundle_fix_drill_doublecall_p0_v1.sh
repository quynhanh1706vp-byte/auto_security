#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drill_doublecall_${TS}"
echo "[BACKUP] $F.bak_drill_doublecall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_DRILL_DOUBLECALL_GUARD_P0_V1"
guard = r"""/* VSP_DRILL_DOUBLECALL_GUARD_P0_V1 */
;(function(){
  'use strict';
  if (window.__VSP_DRILL_DOUBLECALL_GUARD_P0_V1__) return;
  window.__VSP_DRILL_DOUBLECALL_GUARD_P0_V1__ = 1;

  // Unified entrypoint (minimal, safe). Your real impl can override later.
  if (typeof window.VSP_DRILLDOWN !== 'function') {
    window.VSP_DRILLDOWN = function(intent){
      try{
        // default: open datasource tab (commercial fallback)
        if (typeof intent === 'string') intent = { intent:intent };
        var it = (intent && intent.intent) || 'datasource';
        if (it === 'runs') window.location.hash = '#runs';
        else if (it === 'settings') window.location.hash = '#settings';
        else if (it === 'rules') window.location.hash = '#rules';
        else window.location.hash = '#datasource';
        return true;
      }catch(e){
        try{ console.warn('[VSP_DRILLDOWN] err', e); }catch(_){}
        return false;
      }
    };
  }

  function install(name, intent){
    try{
      var desc = Object.getOwnPropertyDescriptor(window, name);
      if (desc && desc.get && String(desc.get).indexOf(MARK) >= 0) return;

      var impl = window[name]; // capture current if any
      Object.defineProperty(window, name, {
        configurable: true,
        enumerable: true,
        get: function VSP_DRILL_DOUBLECALL_GUARD_P0_V1_getter(){
          // return a function that returns a function (double-call safe)
          return function(opts){
            var run = function(){
              try{
                if (typeof impl === 'function') return impl(opts);
                if (typeof window.VSP_DRILLDOWN === 'function') return window.VSP_DRILLDOWN({ intent:intent, opts:opts });
              }catch(e){
                try{ console.warn('[VSP][DRILL] '+name+' err', e); }catch(_){}
              }
            };
            // execute once (so single-call also works), and return callable (for double-call)
            try{ run(); }catch(_){}
            return run;
          };
        },
        set: function(v){ impl = v; }
      });
    }catch(e){
      try{ console.warn('[VSP][DRILL] install fail', name, e); }catch(_){}
    }
  }

  install('VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', 'artifacts');
  install('VSP_DASH_DRILLDOWN_FINDINGS_P1_V2', 'findings');
})();"""

# (A) Replace bare calls to window.* so they go through our guard
def repl_call(name: str, text: str) -> tuple[str,int]:
    pat = re.compile(r'(^|[^\w$\.])' + re.escape(name) + r'\s*\(', flags=re.M)
    new, n = pat.subn(r'\1window.' + name + '(', text)
    return new, n

s2, n1 = repl_call("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2", s)
s2, n2 = repl_call("VSP_DASH_DRILLDOWN_FINDINGS_P1_V2", s2)

# (B) Prefix guard (must be before first top-level usage so bundle won't abort)
if MARK not in s2[:50000]:
    s2 = guard + "\n\n" + s2

p.write_text(s2, encoding="utf-8")
print("[OK] patched bundle:",
      "replaced_calls=" + str(n1+n2),
      "prefixed_guard=" + ("yes" if MARK in s2[:50000] else "no"))
PY

echo "== node --check bundle =="
node --check "$F"
echo "== DONE =="
