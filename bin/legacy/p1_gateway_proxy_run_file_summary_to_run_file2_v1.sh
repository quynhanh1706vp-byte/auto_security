#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq; need awk

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_proxy_runfile_${TS}"
echo "[BACKUP] ${F}.bak_proxy_runfile_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
# === VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V1 ===
def _vsp_proxy_run_file_summary_to_run_file2_wsgi(app):
    """
    If legacy /api/vsp/run_file can't serve reports/SUMMARY.txt (or SHA256SUMS),
    transparently route it to /api/vsp/run_file2 (same rid/name contract).
    """
    from urllib.parse import parse_qs, urlencode

    def wsgi(environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if path == "/api/vsp/run_file" and method == "GET":
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                name = (qs.get("name") or [""])[0] or ""
                # only intercept the problematic ones (minimal risk)
                if name in ("reports/SUMMARY.txt","reports/SHA256SUMS.txt"):
                    environ = dict(environ)
                    environ["PATH_INFO"] = "/api/vsp/run_file2"
                    # keep same query
                    environ["QUERY_STRING"] = urlencode([(k, v2) for k, vv in qs.items() for v2 in vv])
        except Exception:
            pass
        return app(environ, start_response)
    return wsgi
# === /VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V1 ===
'''

apply = r'''
# === VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V1_APPLY ===
try:
    if "application" in globals():
        application = _vsp_proxy_run_file_summary_to_run_file2_wsgi(application)
    elif "app" in globals():
        application = _vsp_proxy_run_file_summary_to_run_file2_wsgi(app)
except Exception:
    pass
# === /VSP_P1_PROXY_RUN_FILE_SUMMARY_TO_RUN_FILE2_V1_APPLY ===
'''

s = s + "\n" + inject + "\n" + apply + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

sudo systemctl restart vsp-ui-8910.service
sleep 1

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "== smoke: SUMMARY via legacy run_file (must be 200 now) =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SUMMARY.txt" | head -n 12

echo "== smoke: SHA via legacy run_file (must be 200 now) =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 12
