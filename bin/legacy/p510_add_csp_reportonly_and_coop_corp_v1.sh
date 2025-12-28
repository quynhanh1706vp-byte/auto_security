#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || T="vsp_demo_app.py"
[ -f "$T" ] || { echo "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p510_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] target=$T backup=$OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY' "$T"
from pathlib import Path
import sys, re
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P510_CSP_REPORTONLY_COOP_CORP_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet=r'''
# VSP_P510_CSP_REPORTONLY_COOP_CORP_V1
# Add CSP Report-Only + COOP/CORP safely for HTML pages (esp /c/*).
try:
    import urllib.parse
except Exception:
    urllib = None

class _VSPHeadersCSPR0V1:
    def __init__(self, app):
        self.app = app

        # Safe CSP Report-Only for current UI: allow self + inline (scripts/styles),
        # data/blob for images/media, connect to self only.
        self.csp_ro = (
            "default-src 'self'; "
            "base-uri 'self'; "
            "object-src 'none'; "
            "frame-ancestors 'self'; "
            "img-src 'self' data: blob:; "
            "font-src 'self' data:; "
            "style-src 'self' 'unsafe-inline'; "
            "script-src 'self' 'unsafe-inline'; "
            "connect-src 'self'; "
            "media-src 'self' blob:; "
            "worker-src 'self' blob:; "
            "form-action 'self'; "
            "upgrade-insecure-requests"
        )

    def _hdr_set(self, headers, name, value):
        n=name.lower()
        out=[]; found=False
        for k,v in headers:
            if (k or "").lower()==n:
                out.append((k,value)); found=True
            else:
                out.append((k,v))
        if not found:
            out.append((name,value))
        return out

    def __call__(self, environ, start_response):
        captured={"status":"200 OK","headers":[],"exc":None}
        write_buf=[]

        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=list(headers or [])
            captured["exc"]=exc_info
            def _write(data):
                if data:
                    write_buf.append(data if isinstance(data,(bytes,bytearray)) else str(data).encode("utf-8","replace"))
            return _write

        it=None
        try:
            it=self.app(environ, _sr)
            body=b"".join(write_buf + list(it or []))
        finally:
            try:
                if hasattr(it,"close"): it.close()
            except Exception:
                pass

        status=captured["status"]
        headers=captured["headers"]

        path=environ.get("PATH_INFO") or ""
        ct=""
        for k,v in headers:
            if (k or "").lower()=="content-type":
                ct=v or ""
                break

        # Apply only to HTML (avoid breaking JSON)
        if "text/html" in (ct or ""):
            headers=self._hdr_set(headers, "Content-Security-Policy-Report-Only", self.csp_ro)
            headers=self._hdr_set(headers, "Cross-Origin-Opener-Policy", "same-origin")
            headers=self._hdr_set(headers, "Cross-Origin-Resource-Policy", "same-origin")
            headers=self._hdr_set(headers, "X-VSP-P510-CSP-RO", "1")

        headers=self._hdr_set(headers, "Content-Length", str(len(body)))
        start_response(status, headers, captured.get("exc"))
        return [body]

def _vsp_p510_wrap(app_obj):
    try:
        if hasattr(app_obj, "wsgi_app"):
            app_obj.wsgi_app = _VSPHeadersCSPR0V1(app_obj.wsgi_app)
            return app_obj
    except Exception:
        pass
    try:
        if callable(app_obj):
            return _VSPHeadersCSPR0V1(app_obj)
    except Exception:
        pass
    return app_obj

try:
    if "app" in globals():
        globals()["app"]=_vsp_p510_wrap(globals()["app"])
    if "application" in globals():
        globals()["application"]=_vsp_p510_wrap(globals()["application"])
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
echo "[OK] patched. Restart service now."
