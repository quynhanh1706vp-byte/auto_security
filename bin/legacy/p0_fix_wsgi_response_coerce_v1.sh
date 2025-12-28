#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_wsgi_coerce_${TS}"
echo "[BACKUP] ${F}.bak_wsgi_coerce_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_WSGI_RESPONSE_COERCE_V1"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P0_WSGI_RESPONSE_COERCE_V1 ---
# Gunicorn WSGI expects an iterable of bytes. If any handler returns a Werkzeug/Flask Response object,
# gunicorn may throw: TypeError: 'Response' object is not iterable.
# Fix: wrap global `application` and coerce Response objects by calling them as WSGI callables.
try:
    _vsp_app_orig = application  # type: ignore[name-defined]
    def application(environ, start_response):  # noqa: F811
        resp = _vsp_app_orig(environ, start_response)

        # If resp is a Werkzeug Response (or compatible), call it to get iterable bytes.
        try:
            from werkzeug.wrappers import Response as _WzResp
        except Exception:
            _WzResp = None

        if _WzResp is not None and isinstance(resp, _WzResp):
            return resp(environ, start_response)

        # Generic: callable + has headers/status ⇒ likely Response-like
        if hasattr(resp, "__call__") and hasattr(resp, "headers") and (hasattr(resp, "status") or hasattr(resp, "status_code")):
            try:
                return resp(environ, start_response)
            except Exception:
                return resp

        return resp
except Exception:
    pass
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
echo "sudo systemctl restart vsp-ui-8910.service"
