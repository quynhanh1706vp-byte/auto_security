#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

B="static/js/vsp_bundle_commercial_v2.js"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$B" "$B.bak_prepend_bridge_${TS}"
cp -f "$APP" "$APP.bak_mtime_cachebust_${TS}"
echo "[BACKUP] $B.bak_prepend_bridge_${TS}"
echo "[BACKUP] $APP.bak_mtime_cachebust_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

# --- (1) PREPEND bridge to bundle (so it runs BEFORE any calls) ---
bp = Path("static/js/vsp_bundle_commercial_v2.js")
s = bp.read_text(encoding="utf-8", errors="replace")

# remove old appended bridge (if any) - it was appended at end
s = re.sub(r'(?s)\n/\* ===================== VSP_DRILLDOWN_BRIDGE_P0_V1.*\Z', '\n', s)

PRE = r'''/* ===================== VSP_DRILLDOWN_BRIDGE_P0_V2_PREPEND ===================== */
/* MUST be at top of bundle: prevent early-call crash */
var VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2;
var VSP_DASH_DRILLDOWN_TOTAL_P1_V2;
var VSP_DASH_DRILLDOWN_CRITICAL_P1_V2;
var VSP_DASH_DRILLDOWN_HIGH_P1_V2;
var VSP_DASH_DRILLDOWN_MEDIUM_P1_V2;
var VSP_DASH_DRILLDOWN_LOW_P1_V2;
var VSP_DASH_DRILLDOWN_INFO_P1_V2;
var VSP_DASH_DRILLDOWN_TRACE_P1_V2;

(function(){
  try{
    if (typeof window.VSP_DRILLDOWN !== 'function') {
      window.VSP_DRILLDOWN = function(intent){
        try{
          // Safe fallback: open datasource tab so UI stays usable
          if (intent && typeof intent === 'object') {
            var i = intent.intent || '';
            if (i === 'datasource' || i === 'total' || i === 'artifacts' || i === 'critical' || i === 'high' || i === 'medium' || i === 'low' || i === 'info' || i === 'trace') {
              if (location && typeof location.hash === 'string') location.hash = '#datasource';
            }
          }
        }catch(_){}
      };
    }

    function mk(intentName){
      return function(){
        try{
          return window.VSP_DRILLDOWN({ intent: intentName, args: Array.prototype.slice.call(arguments) });
        }catch(e){
          try{ console.warn('[VSP][P0] drilldown wrapper failed', intentName, e); }catch(_){}
        }
      };
    }

    function bind(name, intentName){
      if (typeof window[name] !== 'function') window[name] = mk(intentName);
      // also publish as identifier binding via the var declarations above:
      try{
        if (name === 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2') VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_TOTAL_P1_V2') VSP_DASH_DRILLDOWN_TOTAL_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_CRITICAL_P1_V2') VSP_DASH_DRILLDOWN_CRITICAL_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_HIGH_P1_V2') VSP_DASH_DRILLDOWN_HIGH_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_MEDIUM_P1_V2') VSP_DASH_DRILLDOWN_MEDIUM_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_LOW_P1_V2') VSP_DASH_DRILLDOWN_LOW_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_INFO_P1_V2') VSP_DASH_DRILLDOWN_INFO_P1_V2 = window[name];
        if (name === 'VSP_DASH_DRILLDOWN_TRACE_P1_V2') VSP_DASH_DRILLDOWN_TRACE_P1_V2 = window[name];
      }catch(_){}
    }

    bind('VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2', 'artifacts');
    bind('VSP_DASH_DRILLDOWN_TOTAL_P1_V2', 'total');
    bind('VSP_DASH_DRILLDOWN_CRITICAL_P1_V2', 'critical');
    bind('VSP_DASH_DRILLDOWN_HIGH_P1_V2', 'high');
    bind('VSP_DASH_DRILLDOWN_MEDIUM_P1_V2', 'medium');
    bind('VSP_DASH_DRILLDOWN_LOW_P1_V2', 'low');
    bind('VSP_DASH_DRILLDOWN_INFO_P1_V2', 'info');
    bind('VSP_DASH_DRILLDOWN_TRACE_P1_V2', 'trace');

    try{ console.log('[VSP][P0] drilldown bridge PREPEND installed'); }catch(_){}
  }catch(_){}
})();
'''
if "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2" not in s:
    # weird but keep safe
    pass

if "VSP_DRILLDOWN_BRIDGE_P0_V2_PREPEND" not in s:
    s = PRE + "\n" + s

bp.write_text(s, encoding="utf-8")
print("[OK] bundle prepend bridge done:", bp.as_posix(), "bytes=", len(s))

# --- (2) Make /vsp4 bundle tag v=mtime(bundle) to guarantee refresh ---
ap = Path("vsp_demo_app.py")
a = ap.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_AFTERREQ_BUNDLE_MTIME_CACHEBUST_P0_V1"
if MARK not in a:
    # patch inside the existing bundle-only after_request block (P0_V5CLEAN)
    # replace asset_v assignment with mtime-based
    pat = r'(asset_v\s*=\s*m\.group\(1\)\s*if\s*m\s*else\s*"1")'
    if re.search(pat, a):
        repl = (
            'try:\n'
            '            import os as _os\n'
            '            _bf = _os.path.join(_os.path.dirname(__file__), "static", "js", "vsp_bundle_commercial_v2.js")\n'
            '            asset_v = str(int(_os.path.getmtime(_bf))) if _os.path.exists(_bf) else "1"\n'
            '        except Exception:\n'
            '            asset_v = "1"\n'
            f'        # {MARK}\n'
        )
        a = re.sub(pat, repl, a, count=1)
        ap.write_text(a, encoding="utf-8")
        print("[OK] patched vsp_demo_app.py asset_v to mtime(bundle)")
    else:
        print("[WARN] cannot find asset_v line to patch; skipped")
else:
    print("[OK] cachebust marker already present")

PY

node --check "$B" && echo "[OK] node --check bundle OK"
python3 -m py_compile "$APP" && echo "[OK] py_compile OK"

echo "== DONE =="
echo "[NEXT] hardreset 8910 + Ctrl+Shift+R"
