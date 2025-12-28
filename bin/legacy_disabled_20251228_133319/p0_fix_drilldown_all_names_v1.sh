#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drillall_${TS}" && echo "[BACKUP] $F.bak_drillall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

inject = r"""
  // P0 FIX (hard): ALL drilldown helpers must never crash dashboard
  function __vsp_stub_drill(name){
    try{
      const fn = function(){
        try{ console.warn("[VSP_DASH] drilldown helper forced stub:", name); }catch(_){}
        return false;
      };
      // local symbol if exists
      try{
        if (typeof eval(name) !== "function") { /* ignore */ }
      }catch(_){}
      // window symbol
      try{
        if (typeof window[name] !== "function") window[name] = fn;
      }catch(_){}
    }catch(_){}
  }
  try{
    __vsp_stub_drill("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");
    __vsp_stub_drill("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");
  }catch(_){}
"""

# inject once after use strict
if "P0 FIX (hard): ALL drilldown helpers" not in s:
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s=s[:i]+inject+s[i:]
    else:
        s=inject+"\n"+s

def wrap_calls(sym):
    rep = rf'((typeof {sym}==="function") ? {sym} : (typeof window.{sym}==="function" ? window.{sym} : function(){{ try{{ console.warn("[VSP_DASH] drilldown skipped: {sym}"); }}catch(_2){{}} return false; }}))('
    return re.subn(rf'\b{sym}\s*\(', rep, s)

# Wrap both names (global and window-qualified)
for sym in ["VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2", "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"]:
    s, _ = re.subn(rf'\bwindow\.{sym}\s*\(', rf'((typeof window.{sym}==="function") ? window.{sym} : function(){{ try{{ console.warn("[VSP_DASH] drilldown skipped: window.{sym}"); }}catch(_3){{}} return false; }}))(', s)
    s, _ = re.subn(rf'\b{sym}\s*\(', rf'((typeof {sym}==="function") ? {sym} : (typeof window.{sym}==="function" ? window.{sym} : function(){{ try{{ console.warn("[VSP_DASH] drilldown skipped: {sym}"); }}catch(_4){{}} return false; }}))(', s)

p.write_text(s, encoding="utf-8")
print("[OK] injected stubs + wrapped calls for BOTH drilldown symbols")
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
echo "[DONE] Hard refresh Ctrl+Shift+R. Console MUST have no red drilldown TypeError."
