#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_CSP_RO_HARDHOOK_EOF_V3"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_csphard_${TS}"
echo "[BACKUP] ${W}.bak_csphard_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap
p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_CSP_RO_HARDHOOK_EOF_V3" in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

hook = textwrap.dedent(r"""
# ===================== VSP_P1_CSP_RO_HARDHOOK_EOF_V3 =====================
# Force CSP-Report-Only for HTML tabs by wrapping start_response at EOF (wins against rebind/filters).
try:
    _CSP_RO_V3 = (
      "default-src 'self'; img-src 'self' data:; "
      "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; "
      "connect-src 'self'; font-src 'self' data:; "
      "frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    )

    def _csp_ro_wrap(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            def _sr(status, headers, exc_info=None):
                h = list(headers or [])
                keys = {str(k).lower() for (k, _v) in h if k}
                if path in ("/runs","/data_source","/settings","/vsp5"):
                    if "content-security-policy-report-only" not in keys:
                        h.append(("Content-Security-Policy-Report-Only", _CSP_RO_V3))
                return start_response(status, h, exc_info)
            return inner(environ, _sr)
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _csp_ro_wrap(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _csp_ro_wrap(app)

    print("[VSP_P1_CSP_RO_HARDHOOK_EOF_V3] installed")
except Exception as _e:
    print("[VSP_P1_CSP_RO_HARDHOOK_EOF_V3] ERROR:", _e)
# ===================== /VSP_P1_CSP_RO_HARDHOOK_EOF_V3 =====================
""").strip("\n")

p.write_text(s + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended CSP RO hardhook EOF")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== verify FULL HEAD /runs (must show CSP-Report-Only) =="
curl -sS -I "$BASE/runs" | sed -n '1,40p'
echo
echo "== grep CSP only =="
curl -sS -I "$BASE/runs" | grep -i 'content-security-policy-report-only' || true
echo "[DONE]"
