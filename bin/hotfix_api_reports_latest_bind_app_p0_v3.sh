#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_hotfix_reports_${TS}"
echo "[BACKUP] ${F}.bak_hotfix_reports_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_API_REPORTS_LATEST_BIND_APP_P0_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Disable the bad decorator that crashes import (application is a wrapper, not Flask)
s2 = re.sub(
    r'^\s*@application\.route\((["\'])/api/reports/<path:name>\1\s*,\s*methods=\[[^\]]*\]\)\s*$',
    r'# [DISABLED] application is WSGI wrapper (no .route). Bound later via app.add_url_rule',
    s,
    flags=re.M
)

# 2) Append safe binder at end (binds to real Flask app object)
append = r'''
# === VSP_API_REPORTS_LATEST_BIND_APP_P0_V3 ===
from pathlib import Path
from urllib.parse import quote

def _vsp__find_latest_run_with_file__p0v3(relpath: str) -> str:
    base = Path("/home/test/Data/SECURITY_BUNDLE/out")
    if not base.exists():
        return ""
    runs = sorted(base.glob("RUN_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    for rd in runs[:300]:
        try:
            if (rd / relpath).is_file():
                return rd.name
        except Exception:
            continue
    return ""

def vsp_api_reports_latest__p0v3(name):
    rel = name if name.startswith("reports/") else ("reports/" + name)
    rid = _vsp__find_latest_run_with_file__p0v3(rel)
    if not rid:
        return ("Not Found", 404)
    url = "/api/vsp/run_file?rid=" + quote(rid) + "&name=" + quote(rel)
    return ("", 302, {"Location": url})

def _vsp__bind_reports_latest__p0v3():
    # bind to Flask app (usually global "app"); do NOT use "application" wrapper
    flask_app = globals().get("app")
    if not (hasattr(flask_app, "add_url_rule") and hasattr(flask_app, "url_map")):
        # fallback scan
        flask_app = None
        for v in globals().values():
            if hasattr(v, "add_url_rule") and hasattr(v, "url_map") and hasattr(v, "route"):
                flask_app = v
                break
    if not flask_app:
        print("[WARN] cannot locate Flask app to bind /api/reports")
        return False
    try:
        flask_app.add_url_rule(
            "/api/reports/<path:name>",
            endpoint="vsp_api_reports_latest",
            view_func=vsp_api_reports_latest__p0v3,
            methods=["GET","HEAD"]
        )
    except Exception:
        # already bound / endpoint exists
        pass
    return True

_vsp__bind_reports_latest__p0v3()
'''
p.write_text(s2 + "\n\n" + append + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 3; }
echo "[NEXT] restart 8910 then curl /api/reports/run_gate_summary.json again."
