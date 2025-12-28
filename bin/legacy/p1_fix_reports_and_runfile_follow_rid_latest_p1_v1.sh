#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_reports_runfile_latest_${TS}"
echo "[BACKUP] ${F}.bak_reports_runfile_latest_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_REPORTS_RUNFILE_FOLLOW_RIDLATEST_CACHE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''

# --- VSP_P1_REPORTS_RUNFILE_FOLLOW_RIDLATEST_CACHE_V1 ---
# Data-first hardening:
# 1) /api/reports/* always redirects to rid_latest from runs cache (not "some latest RUN_*")
# 2) /api/vsp/run_file when rid/name missing -> fallback redirect to rid_latest (prevents Data Source 404 with stale RID)
import os, json, time
from urllib.parse import urlencode, parse_qs

def _vsp_runs_cache_path():
    return os.environ.get("VSP_RUNS_CACHE_PATH", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/runs_cache_last_good.json")

def _vsp_get_rid_latest_from_cache():
    force = os.environ.get("VSP_REPORTS_ALIAS_FORCE_RID","").strip()
    if force:
        return force
    try:
        b = open(_vsp_runs_cache_path(), "rb").read()
        j = json.loads(b.decode("utf-8","replace"))
        rid = (j.get("rid_latest") or "").strip()
        return rid or None
    except Exception:
        return None

def _vsp_runs_roots():
    roots = os.environ.get("VSP_RUNS_ROOTS", "/home/test/Data/SECURITY_BUNDLE/out").split(":")
    return [r.strip() for r in roots if r.strip()]

def _vsp_safe_rel(name: str) -> bool:
    if not name or name.startswith("/") or "\x00" in name:
        return False
    # prevent traversal
    if ".." in name.split("/"):
        return False
    return True

def _vsp_runfile_exists(rid: str, relname: str) -> bool:
    if not rid or not relname or (not _vsp_safe_rel(relname)):
        return False
    for root in _vsp_runs_roots():
        try:
            base = os.path.join(root, rid)
            if os.path.isdir(base):
                p = os.path.join(base, relname)
                if os.path.isfile(p):
                    return True
        except Exception:
            continue
    return False

class _VspReportsFollowRidLatestMW:
    def __init__(self, app): self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/reports/"):
            return self.app(environ, start_response)
        fname = path[len("/api/reports/"):]  # e.g. findings_unified.json
        if not fname:
            start_response("400 Bad Request",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")])
            return [b'{"ok":false,"error":"missing filename"}']
        rid = _vsp_get_rid_latest_from_cache()
        if not rid:
            start_response("503 Service Unavailable",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),
                                                     ("X-VSP-REPORTS-DEGRADED","1"),("X-VSP-REPORTS-REASON","no_rid_latest_cache")])
            return [b'{"ok":true,"degraded":true,"reason":"no_rid_latest_cache"}']
        qs = urlencode({"rid": rid, "name": f"reports/{fname}"})
        loc = f"/api/vsp/run_file?{qs}"
        start_response("302 Found",[("Location",loc),("Cache-Control","no-store"),
                                   ("X-VSP-REPORTS-ALIAS","rid_latest_cache"),
                                   ("X-VSP-REPORTS-RID",rid)])
        return [b""]

class _VspRunFileFallbackLatestMW:
    def __init__(self, app): self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/api/vsp/run_file":
            return self.app(environ, start_response)

        qs = parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
        rid = (qs.get("rid",[None])[0] or "").strip()
        name = (qs.get("name",[None])[0] or "").strip()

        # Only fallback for safe names (prevent traversal)
        if not _vsp_safe_rel(name):
            return self.app(environ, start_response)

        # If requested file exists -> normal
        if rid and _vsp_runfile_exists(rid, name):
            return self.app(environ, start_response)

        # If missing -> redirect to rid_latest if that file exists
        rid2 = _vsp_get_rid_latest_from_cache()
        if rid2 and _vsp_runfile_exists(rid2, name):
            qs2 = urlencode({"rid": rid2, "name": name})
            loc = f"/api/vsp/run_file?{qs2}"
            start_response("302 Found",[("Location",loc),("Cache-Control","no-store"),
                                       ("X-VSP-RUNFILE-FALLBACK","1"),
                                       ("X-VSP-RUNFILE-OLD", rid or "none"),
                                       ("X-VSP-RUNFILE-NEW", rid2)])
            return [b""]

        # else: let app handle (will 404/503 as before)
        return self.app(environ, start_response)

# Wrap OUTERMOST so it overrides any existing Flask route logic
try:
    application.wsgi_app = _VspRunFileFallbackLatestMW(application.wsgi_app)
    application.wsgi_app = _VspReportsFollowRidLatestMW(application.wsgi_app)
except Exception:
    pass
# --- /VSP_P1_REPORTS_RUNFILE_FOLLOW_RIDLATEST_CACHE_V1 ---
'''
p.write_text(s + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] patch done. Restart UI now."
