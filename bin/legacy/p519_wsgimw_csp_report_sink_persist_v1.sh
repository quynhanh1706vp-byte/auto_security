#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p519_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P519_CSP_REPORT_SINK_PERSIST_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet = r'''
# VSP_P519_CSP_REPORT_SINK_PERSIST_V1
# Intercept /api/ui/csp_report_v1 at WSGI layer and persist to out_ci/csp_reports.log (JSONL).
class _VSPCSPReportSinkPersistV1:
    def __init__(self, app):
        self.app = app
        self.log_path = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log"

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if path == "/api/ui/csp_report_v1":
            if method != "POST":
                body=b'{"ok": false, "err": "method_not_allowed"}'
                start_response("405 Method Not Allowed", [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("Cache-Control","no-store"),
                ])
                return [body]

            # Read request body safely
            try:
                import json, datetime, os
                from pathlib import Path
                cl = int(environ.get("CONTENT_LENGTH") or "0")
                raw = environ["wsgi.input"].read(cl) if cl > 0 else b""
                try:
                    data = json.loads(raw.decode("utf-8","replace") or "{}")
                except Exception:
                    data = {}
                rep = data.get("csp-report") or data.get("report") or data or {}
                out = {
                    "ts": datetime.datetime.now().isoformat(),
                    "document-uri": rep.get("document-uri") or rep.get("documentURL") or "",
                    "blocked-uri": rep.get("blocked-uri") or rep.get("blockedURL") or "",
                    "violated-directive": rep.get("violated-directive") or rep.get("effectiveDirective") or "",
                    "original-policy": (rep.get("original-policy") or "")[:800],
                }
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci").mkdir(parents=True, exist_ok=True)
                with open(self.log_path, "a", encoding="utf-8") as f:
                    f.write(json.dumps(out, ensure_ascii=False) + "\n")
            except Exception:
                pass

            body=b'{"ok": true}'
            start_response("200 OK", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Cache-Control","no-store"),
                ("X-VSP-P519-CSP-LOG","1"),
            ])
            return [body]

        return self.app(environ, start_response)

def _vsp_p519_wrap(app_obj):
    try:
        if callable(app_obj):
            return _VSPCSPReportSinkPersistV1(app_obj)
    except Exception:
        pass
    return app_obj

# Prefer wrapping the final "application" so it catches even when Flask forcebind is skipped.
try:
    if "application" in globals():
        globals()["application"] = _vsp_p519_wrap(globals()["application"])
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== POST test =="
curl -sS -D- -o /dev/null -X POST -H 'Content-Type: application/json' \
  --data '{"csp-report":{"document-uri":"persist-test","blocked-uri":"x","violated-directive":"script-src"}}' \
  "$BASE/api/ui/csp_report_v1" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P519-CSP-LOG:/{print}'

echo "== tail log =="
tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log
