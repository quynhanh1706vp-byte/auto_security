#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_drillrewire_${TS}" && echo "[BACKUP] $F.bak_drillrewire_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

# Ensure window helper is always a function stub
stub = r"""
  // P0 FIX (final2): ensure drilldown helper exists on window (function)
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn("[VSP_DASH] drilldown forced stub (window)"); }catch(_){}
        return false;
      };
    }
  }catch(_){}
"""
if "P0 FIX (final2): ensure drilldown helper exists on window" not in s:
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s=s[:i]+stub+s[i:]
    else:
        s=stub+"\n"+s

name = "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"
wname = f"window.{name}"

# 1) Rewrite ALL direct calls + call/apply/bind to window.*
s, n_call  = re.subn(rf'(?<![\w$.]){name}\s*\(', rf'{wname}(', s)
s, n_call2 = re.subn(rf'(?<![\w$.]){name}\s*\.call\s*\(', rf'{wname}.call(', s)
s, n_app   = re.subn(rf'(?<![\w$.]){name}\s*\.apply\s*\(', rf'{wname}.apply(', s)
s, n_bind  = re.subn(rf'(?<![\w$.]){name}\s*\.bind\s*\(', rf'{wname}.bind(', s)

# 2) Rewrite RHS references that may be stored then called later:
#    a) assignments: = VSP_...
s, n_eq = re.subn(rf'(\=\s*){name}\b', rf'\1{wname}', s)
#    b) object literal: : VSP_...
s, n_col = re.subn(rf'(\:\s*){name}\b', rf'\1{wname}', s)
#    c) parentheses return: return VSP_...
s, n_ret = re.subn(rf'(\breturn\s+){name}\b', rf'\1{wname}', s)

p.write_text(s, encoding="utf-8")
print("[OK] rewired drilldown refs to window.*",
      {"call":n_call,"call2":n_call2,"apply":n_app,"bind":n_bind,"eq":n_eq,"colon":n_col,"ret":n_ret})
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
