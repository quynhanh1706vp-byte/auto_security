#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# Endpoint dễ nhất là patch trực tiếp vào vsp_demo_app.py nếu tồn tại
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing vsp_demo_app.py (needed for report endpoint)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p512_${TS}"
mkdir -p "$OUT"
cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P512_CSP_REPORT_ENDPOINT_V1"
if MARK not in s:
    # Ensure imports
    if "from flask import" in s and "request" not in s:
        s=re.sub(r"from flask import ([^\n]+)", lambda m: m.group(0).rstrip()+" , request", s, count=1)
    elif "import flask" not in s and "from flask import" not in s:
        # very defensive: don't guess; just proceed without changing imports
        pass

    endpoint = r'''
# VSP_P512_CSP_REPORT_ENDPOINT_V1
try:
    import json, datetime
except Exception:
    json = None
    datetime = None

@app.route("/api/ui/csp_report_v1", methods=["POST"])
def api_ui_csp_report_v1():
    # Accept JSON reports; log minimal summary to avoid noise
    try:
        data = request.get_json(silent=True) or {}
    except Exception:
        data = {}
    rep = data.get("csp-report") or data.get("report") or data
    out = {
        "ts": (datetime.datetime.now().isoformat() if datetime else ""),
        "document-uri": rep.get("document-uri") or rep.get("documentURL") or "",
        "blocked-uri": rep.get("blocked-uri") or rep.get("blockedURL") or "",
        "violated-directive": rep.get("violated-directive") or rep.get("effectiveDirective") or "",
        "original-policy": (rep.get("original-policy") or "")[:300],
    }
    try:
        # send to stderr / gunicorn log
        print("[CSP-REPORT]", out, flush=True)
    except Exception:
        pass
    return {"ok": True}
'''
    # Append near end
    s = s.rstrip() + "\n\n" + endpoint + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile vsp_demo_app.py"

echo "[OK] now wire report-uri into CSP via wsgi_vsp_ui_gateway.py (P510 block)"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P510_CSP_REPORTONLY_COOP_CORP_V1"
if MARK not in s:
    print("[ERR] P510 marker not found in wsgi_vsp_ui_gateway.py")
    raise SystemExit(2)

# add report-uri if not present
if "report-uri /api/ui/csp_report_v1" not in s:
    s = s.replace("upgrade-insecure-requests", "upgrade-insecure-requests; report-uri /api/ui/csp_report_v1")
p.write_text(s, encoding="utf-8")
print("[OK] wired report-uri")
PY

echo "[OK] restart service"
sudo systemctl restart vsp-ui-8910.service
