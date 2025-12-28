#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_enhance_v1.js"
T="templates/vsp_4tabs_commercial_v1.html"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drill_v4_${TS}" && echo "[BACKUP] $F.bak_drill_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

NAME="VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"
SHADOW="__VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2_SHADOW"

# A) Rename any declarations that create a non-window binding (shadow)
s, n_decl_var = re.subn(rf'\b(const|let|var)\s+{NAME}\b', rf'\1 {SHADOW}', s)
s, n_decl_fn  = re.subn(rf'\bfunction\s+{NAME}\b', rf'function {SHADOW}', s)

# B) Ensure a dispatcher exists (always calls window.NAME if it's a function)
inject = r"""
  // P0 FIX v4 (commercial): drilldown dispatcher + hard guard
  function __vsp_call_drilldown_artifacts(){
    try{
      const fn = (window && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")
        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2
        : function(){ try{ console.warn("[VSP_DASH] drilldown skipped (no window func)"); }catch(_){ } return false; };
      return fn.apply(null, arguments);
    }catch(_){
      try{ console.warn("[VSP_DASH] drilldown dispatcher failed -> skipped"); }catch(__){}
      return false;
    }
  }
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn("[VSP_DASH] drilldown forced stub (window)"); }catch(_){}
        return false;
      };
    }
    console.log("[VSP_DASH] drilldown v4 loaded");
  }catch(_){}
"""
if "__vsp_call_drilldown_artifacts" not in s:
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s=s[:i]+inject+s[i:]
    else:
        s=inject+"\n"+s

# C) Rewire ALL call sites (direct call + call/apply/bind)
s, n_call  = re.subn(rf'(?<![\w$.]){NAME}\s*\(', r'__vsp_call_drilldown_artifacts(', s)
s, n_call2 = re.subn(rf'\bwindow\.{NAME}\s*\(', r'__vsp_call_drilldown_artifacts(', s)
s, n_call3 = re.subn(rf'(?<![\w$.]){NAME}\s*\.(call|apply|bind)\s*\(', r'window.'+NAME+r'.\1(', s)

# D) Rewire stored references (so no “cache old non-function”)
s, n_eq  = re.subn(rf'(\=\s*){NAME}\b', r'\1window.'+NAME, s)
s, n_col = re.subn(rf'(\:\s*){NAME}\b', r'\1window.'+NAME, s)
s, n_ret = re.subn(rf'(\breturn\s+){NAME}\b', r'\1window.'+NAME, s)

p.write_text(s, encoding="utf-8")
print("[OK] drilldown v4 patched:",
      {"decl_var":n_decl_var,"decl_fn":n_decl_fn,"call":n_call,"call_win":n_call2,"call_meth":n_call3,"eq":n_eq,"colon":n_col,"ret":n_ret})
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

# Cache-bust template for this JS to guarantee browser loads new code
if [ -f "$T" ]; then
  cp -f "$T" "$T.bak_drill_v4_${TS}" && echo "[BACKUP] $T.bak_drill_v4_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$T")
s=p.read_text(encoding="utf-8")
ts="$TS"
s2, n = re.subn(r'(\/static\/js\/vsp_dashboard_enhance_v1\.js)(\?v=[0-9_]+)?', r'\1?v='+ts, s)
p.write_text(s2, encoding="utf-8")
print("[OK] template cachebust patched:", n)
PY
fi

# restart 8910
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.2
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] DevTools -> Reload (Empty cache and hard reload). Look for: [VSP_DASH] drilldown v4 loaded"
