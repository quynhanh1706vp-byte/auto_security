#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) Fix drilldown JS: guard inside dashboard enhance =="
JSF="$(ls -1 static/js/*dashboard*enhanc*.js 2>/dev/null | head -n1 || true)"
if [ -z "${JSF:-}" ]; then
  echo "[WARN] cannot find dashboard enhance js under static/js/*dashboard*enhanc*.js (skip)"
else
  cp -f "$JSF" "$JSF.bak_dd_guard_${TS}" && echo "[BACKUP] $JSF.bak_dd_guard_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("$JSF")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_DD_GUARD_LOCAL_V1" in s:
    print("[OK] dd guard already present")
else:
    guard = r'''
  // VSP_DD_GUARD_LOCAL_V1: never crash if drilldown symbol isn't a function
  try{
    function __vsp_dd_stub(){
      try{ console.info("[VSP][DD] local stub invoked"); }catch(_){}
      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};
    }
    if (typeof window !== "undefined") {
      if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
        window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_stub;
      }
    }
  }catch(_){}
'''
    # insert right after first 'use strict'
    i = s.find("'use strict'")
    if i != -1:
        j = s.find(";", i)
        if j != -1:
            s = s[:j+1] + guard + s[j+1:]
        else:
            s = guard + s
    else:
        s = guard + s

    p.write_text(s, encoding="utf-8")
    print("[OK] injected dd guard into", p)
PY
  node --check "$JSF" >/dev/null && echo "[OK] node --check: $JSF"
fi

echo "== (2) Fix favicon 404: redirect /favicon.ico and /vsp4/favicon.ico to /static/favicon.ico =="
PYF="vsp_demo_app.py"
if [ -f "$PYF" ]; then
  cp -f "$PYF" "$PYF.bak_faviconredir_${TS}" && echo "[BACKUP] $PYF.bak_faviconredir_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

m=re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...) in vsp_demo_app.py")
appvar=m.group(1)

if "VSP_FAVICON_REDIRECT_V1" in s:
    print("[OK] favicon redirect already present")
else:
    s += f"""

# ================================
# VSP_FAVICON_REDIRECT_V1
# ================================
@{appvar}.before_request
def __vsp_favicon_redirect_v1():
  try:
    pth = request.path or ""
    if pth == "/favicon.ico" or pth == "/vsp4/favicon.ico":
      return redirect("/static/favicon.ico", code=302)
  except Exception:
    pass
  return None
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended favicon redirect v1 on", appvar)
PY
  python3 -m py_compile "$PYF" && echo "[OK] py_compile OK: $PYF"
else
  echo "[WARN] missing vsp_demo_app.py (skip favicon redirect patch)"
fi

echo "== (3) Restart 8910 (NO restore) =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  PIDF="out_ci/ui_8910.pid"
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid "$PIDF" \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "== (4) Quick verify =="
curl -sSI http://127.0.0.1:8910/vsp4/favicon.ico | head -n 6 || true
echo "[NEXT] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp4/#dashboard và click #runs/#datasource/#settings/#rules"
