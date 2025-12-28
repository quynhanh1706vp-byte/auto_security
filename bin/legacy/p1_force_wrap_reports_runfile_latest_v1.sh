#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_forcewrap_reports_${TS}"
echo "[BACKUP] ${F}.bak_forcewrap_reports_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FORCE_WRAP_REPORTS_RUNFILE_LATEST_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

inject = r'''

# --- VSP_P1_FORCE_WRAP_REPORTS_RUNFILE_LATEST_V1 ---
# Force WSGI wrapping at module-level `application` (works even if `application` is not Flask).
import os, json, time, glob
from urllib.parse import urlencode, parse_qs

def _vsp_roots():
    roots = os.environ.get("VSP_RUNS_ROOTS", "/home/test/Data/SECURITY_BUNDLE/out").split(":")
    return [r.strip() for r in roots if r.strip()]

def _safe_rel(name: str) -> bool:
    if not name or name.startswith("/") or "\x00" in name:
        return False
    if ".." in name.split("/"):
        return False
    return True

def _runfile_exists(rid: str, relname: str) -> bool:
    if not rid or not relname or (not _safe_rel(relname)):
        return False
    for root in _vsp_roots():
        try:
            base = os.path.join(root, rid)
            if os.path.isdir(base):
                p = os.path.join(base, relname)
                if os.path.isfile(p):
                    return True
        except Exception:
            continue
    return False

def _rid_latest_from_runs_cache():
    # If force env set, obey
    force = os.environ.get("VSP_REPORTS_ALIAS_FORCE_RID", "").strip()
    if force:
        return force

    # Try find newest cache file in ui/out_ci
    cand = []
    try:
        ui_out_ci = os.path.join(os.path.dirname(__file__), "out_ci")
        pats = [
            os.path.join(ui_out_ci, "runs_cache*.json"),
            os.path.join(ui_out_ci, "*runs*cache*.json"),
            os.path.join(ui_out_ci, "vsp_runs*.json"),
        ]
        for pat in pats:
            for f in glob.glob(pat):
                try:
                    cand.append((os.path.getmtime(f), f))
                except Exception:
                    pass
    except Exception:
        pass

    cand.sort(reverse=True)
    for _, f in cand[:5]:
        try:
            j = json.loads(open(f, "rb").read().decode("utf-8","replace"))
            rid = (j.get("rid_latest") or "").strip()
            if rid:
                return rid
        except Exception:
            continue

    # Fallback: scan roots, prefer VSP_CI_RUN_*, then any *_RUN_*/RUN_*
    best = None
    best_m = -1
    prefer = None
    prefer_m = -1
    for root in _vsp_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."): 
                    continue
                pth = os.path.join(root, name)
                if not os.path.isdir(pth) and not os.path.islink(pth):
                    continue
                try:
                    m = os.path.getmtime(pth)
                except Exception:
                    continue
                if name.startswith("VSP_CI_RUN_"):
                    if m > prefer_m:
                        prefer_m = m
                        prefer = name
                if ("_RUN_" in name) or name.startswith("RUN_"):
                    if m > best_m:
                        best_m = m
                        best = name
        except Exception:
            continue
    return prefer or best

class _ForceWrapReportsRunFileMW:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs_raw = (environ.get("QUERY_STRING") or "")

        # 1) /api/reports/<file> -> redirect to rid_latest + reports/<file>
        if path.startswith("/api/reports/"):
            fname = path[len("/api/reports/"):]
            rid = _rid_latest_from_runs_cache()
            if not fname:
                start_response("400 Bad Request",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store")])
                return [b'{"ok":false,"error":"missing filename"}']
            if not rid:
                start_response("503 Service Unavailable",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),
                                                         ("X-VSP-REPORTS-DEGRADED","1"),("X-VSP-REPORTS-REASON","no_rid_latest")])
                return [b'{"ok":true,"degraded":true,"reason":"no_rid_latest"}']
            loc = "/api/vsp/run_file?" + urlencode({"rid": rid, "name": f"reports/{fname}"})
            start_response("302 Found",[("Location",loc),("Cache-Control","no-store"),
                                        ("X-VSP-REPORTS-ALIAS","rid_latest"),
                                        ("X-VSP-REPORTS-RID",rid)])
            return [b""]

        # 2) /api/vsp/run_file fallback:
        # if rid is stale and file missing => redirect to rid_latest if file exists there
        if path == "/api/vsp/run_file":
            qs = parse_qs(qs_raw, keep_blank_values=True)
            rid = (qs.get("rid",[None])[0] or "").strip()
            name = (qs.get("name",[None])[0] or "").strip()

            if _safe_rel(name):
                if (not rid) or (not _runfile_exists(rid, name)):
                    rid2 = _rid_latest_from_runs_cache()
                    if rid2 and _runfile_exists(rid2, name):
                        loc = "/api/vsp/run_file?" + urlencode({"rid": rid2, "name": name})
                        start_response("302 Found",[("Location",loc),("Cache-Control","no-store"),
                                                    ("X-VSP-RUNFILE-FALLBACK","1"),
                                                    ("X-VSP-RUNFILE-OLD", rid or "none"),
                                                    ("X-VSP-RUNFILE-NEW", rid2)])
                        return [b""]

        return self.app(environ, start_response)

# FORCE wrap callable application (outermost)
try:
    _orig_app = application
    application = _ForceWrapReportsRunFileMW(_orig_app)
except Exception:
    pass
# --- /VSP_P1_FORCE_WRAP_REPORTS_RUNFILE_LATEST_V1 ---
'''
p.write_text(s + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] patch done. Restart UI."
