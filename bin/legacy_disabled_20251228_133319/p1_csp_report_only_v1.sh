#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_CSP_REPORT_ONLY_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_csp_${TS}"
echo "[BACKUP] ${W}.bak_csp_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_CSP_REPORT_ONLY_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

anchor = "# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
idx = s.find(anchor)
if idx < 0: idx = len(s)

patch = textwrap.dedent(r"""
# ===================== VSP_P1_CSP_REPORT_ONLY_V1 =====================
# Add CSP in Report-Only mode for HTML pages (safe, non-breaking).
try:
    _CSP_RO = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " \
              "script-src 'self' 'unsafe-inline'; connect-src 'self'; font-src 'self' data:; " \
              "frame-ancestors 'none'; base-uri 'self'; form-action 'self'"

    def _wrap_csp_ro(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            def _sr(status, headers, exc_info=None):
                h = list(headers or [])
                # Only for HTML routes (tabs). Keep APIs untouched.
                if path in ("/runs","/data_source","/settings","/vsp5"):
                    h.append(("Content-Security-Policy-Report-Only", _CSP_RO))
                return start_response(status, h, exc_info)
            return inner(environ, _sr)
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_csp_ro(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_csp_ro(app)

    print("[VSP_P1_CSP_REPORT_ONLY_V1] enabled")
except Exception as _e:
    print("[VSP_P1_CSP_REPORT_ONLY_V1] ERROR:", _e)
# ===================== /VSP_P1_CSP_REPORT_ONLY_V1 =====================
""")

p.write_text(s[:idx] + patch + "\n" + s[idx:], encoding="utf-8")
print("[OK] patched CSP-RO")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke HEAD /runs (must contain CSP-Report-Only) =="
curl -sS -I "$BASE/runs" | egrep -i 'HTTP/|content-security-policy-report-only|cache-control|x-frame-options|x-content-type-options' || true
echo "[DONE]"
