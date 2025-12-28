#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p34_csp_ro_wsgiwrap_${TS}"
echo "[BACKUP] ${W}.bak_p34_csp_ro_wsgiwrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P34_CSP_RO_WSGI_WRAP_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    # Keep policy aligned with what other tabs already use in your headers
    csp = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"

    block=f"""
# --- {MARK} ---
# Commercial: inject CSP-Report-Only at WSGI layer so cached GET (/vsp5 HIT-RAM/HIT-DISK) is covered too.
__vsp_p34_wrapped_v3 = globals().get("__vsp_p34_wrapped_v3", False)

def __vsp_p34_wrap_start_response_v3(start_response):
    def _sr(status, headers, exc_info=None):
        try:
            # headers: list[tuple[str,str]]
            ct = ""
            has = False
            for k,v in headers:
                lk = (k or "").lower()
                if lk == "content-type":
                    ct = (v or "").lower()
                elif lk == "content-security-policy-report-only":
                    has = True
            if ("text/html" in ct) and (not has):
                headers.append(("Content-Security-Policy-Report-Only", "{csp}"))
        except Exception:
            pass
        return start_response(status, headers, exc_info)
    return _sr

try:
    if not __vsp_p34_wrapped_v3:
        _orig_app = globals().get("application", None)
        if callable(_orig_app):
            def application(environ, start_response):
                return _orig_app(environ, __vsp_p34_wrap_start_response_v3(start_response))
            globals()["__vsp_p34_wrapped_v3"] = True
except Exception:
    pass
# --- /{MARK} ---
"""
    s = s.rstrip() + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^${SVC}"; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"
fi

echo "== [CHECK] GET header on /vsp5 (must include CSP_RO) =="
curl -fsS -D- -o /dev/null "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Security-Policy-Report-Only:/{print}'

echo "== [RUN] commercial_ui_audit_v2 (tail) =="
BASE="$BASE" bash bin/commercial_ui_audit_v2.sh | tail -n 90
