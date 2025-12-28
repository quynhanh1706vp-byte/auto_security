#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq; need awk

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_directserve_${TS}"
echo "[BACKUP] ${F}.bak_directserve_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DIRECT_SERVE_SUMMARY_SHA_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
# === VSP_P1_DIRECT_SERVE_SUMMARY_SHA_V1 ===
def _vsp_direct_serve_summary_sha_wsgi(app):
    """
    Commercial-safe: ensure legacy /api/vsp/run_file can serve:
      - reports/SUMMARY.txt
      - reports/SHA256SUMS.txt
    for both GET and HEAD, by reading files directly from OUT_ROOT.
    """
    import os
    from pathlib import Path
    from urllib.parse import parse_qs

    OUT_ROOT = Path("/home/test/Data/SECURITY_BUNDLE/out")

    def _send(start_response, code, headers, body=b""):
        start_response(code, headers)
        return [body] if body else [b""]

    def wsgi(environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if path == "/api/vsp/run_file" and method in ("GET","HEAD"):
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0].strip()
                name = (qs.get("name") or [""])[0].strip()
                if rid and name in ("reports/SUMMARY.txt","reports/SHA256SUMS.txt"):
                    fp = (OUT_ROOT / rid / name).resolve()
                    rd = (OUT_ROOT / rid).resolve()
                    if str(fp).find(str(rd)) != 0:
                        return _send(start_response, "400 BAD REQUEST", [
                            ("Content-Type","application/json; charset=utf-8"),
                            ("X-VSP-DirectServe", MARK),
                        ], b'{"ok":false,"err":"path traversal"}')
                    if fp.exists() and fp.is_file():
                        try:
                            st = fp.stat()
                            clen = str(int(st.st_size))
                        except Exception:
                            clen = None
                        headers = [
                            ("Content-Type","text/plain; charset=utf-8"),
                            ("Content-Disposition", f'attachment; filename={os.path.basename(name)}'),
                            ("Cache-Control","no-cache"),
                            ("X-VSP-DirectServe", MARK),
                        ]
                        if clen:
                            headers.append(("Content-Length", clen))
                        if method == "HEAD":
                            return _send(start_response, "200 OK", headers, b"")
                        body = fp.read_bytes()
                        return _send(start_response, "200 OK", headers, body)
        except Exception:
            pass
        return app(environ, start_response)

    return wsgi
# === /VSP_P1_DIRECT_SERVE_SUMMARY_SHA_V1 ===
'''

apply = r'''
# === VSP_P1_DIRECT_SERVE_SUMMARY_SHA_V1_APPLY ===
try:
    if "application" in globals():
        application = _vsp_direct_serve_summary_sha_wsgi(application)
    elif "app" in globals():
        application = _vsp_direct_serve_summary_sha_wsgi(app)
except Exception:
    pass
# === /VSP_P1_DIRECT_SERVE_SUMMARY_SHA_V1_APPLY ===
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
RID="$(curl -sS "$BASE/api/vsp/runs?limit=50" | jq -r '.items[] | select(.run_id!="A2Z_INDEX") | .run_id' | head -n1)"
echo "RID=$RID"

echo "== smoke HEAD SUMMARY via legacy run_file (must be 200 now) =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SUMMARY.txt" | head -n 15

echo "== smoke HEAD SHA via legacy run_file (should be 200) =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 15
