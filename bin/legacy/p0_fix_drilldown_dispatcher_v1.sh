#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drilldisp_${TS}" && echo "[BACKUP] $F.bak_drilldisp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

inject = r"""
  // P0 FIX (final): drilldown dispatcher (avoid shadowed non-function symbols)
  function __vsp_call_drilldown_artifacts(){
    try{
      const fn = (window && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")
        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2
        : function(){ try{ console.warn("[VSP_DASH] drilldown skipped (no function on window)"); }catch(_){ } return false; };
      return fn.apply(null, arguments);
    }catch(_){
      try{ console.warn("[VSP_DASH] drilldown dispatcher failed -> skipped"); }catch(__){}
      return false;
    }
  }
"""
if "__vsp_call_drilldown_artifacts" not in s:
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s=s[:i]+inject+s[i:]
    else:
        s=inject+"\n"+s

# Replace ANY direct calls to the problematic helper with dispatcher
s, n1 = re.subn(r'(?<![\w$.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(',
                r'__vsp_call_drilldown_artifacts(',
                s)
s, n2 = re.subn(r'\bwindow\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(',
                r'__vsp_call_drilldown_artifacts(',
                s)

p.write_text(s, encoding="utf-8")
print(f"[OK] injected dispatcher + rewired calls: bare={n1}, window={n2}")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

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
echo "[DONE] DevTools Reload -> Empty cache and hard reload. Red drilldown TypeError must be gone."
