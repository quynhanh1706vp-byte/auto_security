#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_forcewin_${TS}" && echo "[BACKUP] $F.bak_forcewin_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8")

# 1) Ensure window symbol is always a function
stub = r"""
  // P0 FIX (final): force drilldown helper onto window and call window.* to avoid shadowed const/object
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn("[VSP_DASH] drilldown forced stub (window)"); }catch(_){}
        return false;
      };
    }
  }catch(_){}
"""
if "P0 FIX (final): force drilldown helper onto window" not in s:
    m=re.search(r"(['\"]use strict['\"];\s*)", s)
    if m:
        i=m.end(1)
        s = s[:i] + stub + s[i:]
    else:
        s = stub + "\n" + s

# 2) Rewrite ALL bare calls to window.* to bypass any shadowed local binding
#    Replace: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(  -> window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(
s, n = re.subn(r'(?<![\w$.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(',
               r'window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(',
               s)

# 3) Also cover bracket-call style if exists: ["VSP_..."]( -> window["VSP_..."](
s = s.replace('["VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"](', 'window["VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2"](')

p.write_text(s, encoding="utf-8")
print(f"[OK] forced window stub + rewrote bare calls => window.* (n_calls={n})")
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
echo "[DONE] Empty cache & hard reload, drilldown TypeError must be gone."
