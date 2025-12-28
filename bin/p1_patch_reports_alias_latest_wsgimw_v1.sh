#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_reports_alias_latest_${TS}"
echo "[BACKUP] ${F}.bak_reports_alias_latest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_REPORTS_ALIAS_LATEST_WSGIMW_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

inject = r'''

# --- VSP_P1_REPORTS_ALIAS_LATEST_WSGIMW_V1 ---
# Ensure /api/reports/* always targets current rid_latest (so UI dashboard never shows stale RID)
import os, json, time
from urllib.parse import urlencode

def _vsp_pick_rid_latest():
    roots = os.environ.get("VSP_RUNS_ROOTS","/home/test/Data/SECURITY_BUNDLE/out").split(":")
    roots = [r.strip() for r in roots if r.strip()]
    best = None
    best_m = -1
    for root in roots:
        try:
            for name in os.listdir(root):
                if name.startswith("."): 
                    continue
                pth = os.path.join(root, name)
                if not os.path.isdir(pth):
                    continue
                # accept things that look like run dirs, including our alias VSP_CI_RUN_*
                if ("_RUN_" not in name) and (not name.startswith("RUN_")) and (not name.startswith("VSP_CI_RUN_")):
                    continue
                try:
                    m = os.path.getmtime(pth)
                except Exception:
                    continue
                if m > best_m:
                    best_m = m
                    best = name
        except Exception:
            continue
    return best

class _VspReportsAliasLatestMW:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/reports/"):
            return self.app(environ, start_response)

        # map /api/reports/<file> -> /api/vsp/run_file?rid=<rid_latest>&name=reports/<file>
        rid = _vsp_pick_rid_latest()
        fname = path[len("/api/reports/"):]  # e.g. run_gate_summary.json
        if not fname:
            payload = {"ok": False, "error":"missing filename", "ts": int(time.time())}
            b = json.dumps(payload).encode("utf-8")
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")])
            return [b]
        if not rid:
            payload = {"ok": False, "error":"no rid_latest", "ts": int(time.time())}
            b = json.dumps(payload).encode("utf-8")
            start_response("404 Not Found", [("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")])
            return [b]

        qs = urlencode({"rid": rid, "name": f"reports/{fname}"})
        loc = f"/api/vsp/run_file?{qs}"
        hdrs = [("Location", loc),
                ("Cache-Control","no-store"),
                ("X-VSP-REPORTS-ALIAS","latest"),
                ("X-VSP-REPORTS-RID", rid)]
        start_response("302 Found", hdrs)
        return [b""]

try:
    application.wsgi_app = _VspReportsAliasLatestMW(application.wsgi_app)
except Exception:
    pass
# --- /VSP_P1_REPORTS_ALIAS_LATEST_WSGIMW_V1 ---
'''
p.write_text(s + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] patch done. Restart UI."
