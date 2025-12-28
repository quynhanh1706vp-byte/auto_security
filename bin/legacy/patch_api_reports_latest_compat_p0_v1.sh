#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_apireports_${TS}"
echo "[BACKUP] ${F}.bak_apireports_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_API_REPORTS_LATEST_COMPAT_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# we expect gunicorn points to wsgi_vsp_ui_gateway:application
# ensure imports exist
need_imports = [
    "from pathlib import Path",
    "import os",
    "from urllib.parse import quote",
]
for imp in need_imports:
    if imp not in s:
        # insert near top after existing imports
        s = re.sub(r"(^import .*?$)", r"\1\n"+imp, s, count=1, flags=re.M)

# find 'application =' or Flask creation area to inject after app created
m = re.search(r"^(application\s*=\s*Flask\([^\n]*\)\s*)$", s, flags=re.M)
if not m:
    # fallback: first occurrence of "application ="
    m = re.search(r"^application\s*=.*$", s, flags=re.M)

inject = r'''
# === VSP_API_REPORTS_LATEST_COMPAT_P0_V1 ===
def _vsp__find_latest_run_with_file(relpath: str) -> str:
    """
    Return RUN_ID (folder basename) of newest out/RUN_* that contains relpath.
    relpath examples: 'reports/index.html' or 'reports/run_gate_summary.json'
    """
    base = Path("/home/test/Data/SECURITY_BUNDLE/out")
    if not base.exists():
        return ""
    # newest first by mtime
    runs = sorted(base.glob("RUN_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    for rd in runs[:200]:
        try:
            fp = rd / relpath
            if fp.is_file():
                return rd.name
        except Exception:
            continue
    return ""

@application.route("/api/reports/<path:name>", methods=["GET","HEAD"])
def vsp_api_reports_latest(name):
    # compat endpoint: serve latest run's report file via run_file contract
    # /api/reports/run_gate_summary.json  -> reports/run_gate_summary.json
    rel = name
    if not rel.startswith("reports/"):
        rel = "reports/" + rel

    rid = _vsp__find_latest_run_with_file(rel)
    if not rid:
        return ("Not Found", 404)

    # redirect to commercial contract endpoint
    url = "/api/vsp/run_file?rid=" + quote(rid) + "&name=" + quote(rel)
    return ("", 302, {"Location": url})
'''

if m:
    pos = m.end()
    s = s[:pos] + "\n" + inject + "\n" + s[pos:]
else:
    # append at end as fallback
    s = s + "\n" + inject + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 3; }
echo "[NEXT] restart UI service/gunicorn then retry /api/reports/run_gate_summary.json"
