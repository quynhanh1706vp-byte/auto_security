#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_ds_lazy_nostore_${TS}"
echo "[BACKUP] ${W}.bak_ds_lazy_nostore_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P1_DS_LAZY_STATIC_NOSTORE_V1"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

addon = r'''
# --- VSP_P1_DS_LAZY_STATIC_NOSTORE_V1 ---
class __VspNoStoreDsLazyMW:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/static/js/vsp_data_source_lazy_v1.js":
            return self.app(environ, start_response)

        status_box = {}
        def _sr(status, headers, exc_info=None):
            # Force no-store for this one file (avoid stale cached DS logic)
            hdrs = list(headers or [])
            hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "cache-control"]
            hdrs.append(("Cache-Control", "no-store"))
            status_box["status"]=status
            status_box["headers"]=hdrs
            status_box["exc_info"]=exc_info
            return start_response(status, hdrs, exc_info)
        return self.app(environ, _sr)

try:
    application = __VspNoStoreDsLazyMW(application)
except Exception:
    try:
        app = __VspNoStoreDsLazyMW(app)
    except Exception:
        pass
# --- /VSP_P1_DS_LAZY_STATIC_NOSTORE_V1 ---
'''
p.write_text(s.rstrip()+"\n"+addon+"\n", encoding="utf-8")
print("[OK] appended no-store MW for DS lazy static")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
