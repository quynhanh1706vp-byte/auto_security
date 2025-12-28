#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fillreal_tail_${TS}"
echo "[BACKUP] ${F}.bak_fillreal_tail_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_GATEWAY_FORCE_FILLREAL_TAIL_P1_V4"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# ensure middleware class exists (use existing from V3 if present)
if "class _VspHtmlInjectMw" not in s:
    mw = r'''
# === VSP_GATEWAY_INJECT_FILLREAL_WSGI_MW_P1_V4 ===
import re as _re

class _VspHtmlInjectMw:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        captured = {"status": None, "headers": None, "exc": None, "write": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # return a write callable (WSGI)
            def _write(_data):
                return None
            captured["write"] = _write
            return _write

        app_iter = self.app(environ, _sr)

        try:
            chunks=[]
            for c in app_iter:
                if c:
                    chunks.append(c)
            body = b"".join(chunks)
        finally:
            try:
                close=getattr(app_iter,"close",None)
                if callable(close): close()
            except Exception:
                pass

        headers = captured["headers"] or []
        ct = ""
        for (k,v) in headers:
            if str(k).lower() == "content-type":
                ct = str(v).lower()
                break

        if "text/html" in ct and body:
            try:
                html = body.decode("utf-8", errors="replace")
                if ("vsp_fill_real_data_5tabs_p1_v1.js" not in html) and ("VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" not in html):
                    tag = (
                        "\n<!-- VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
                        "<script src=\"/static/js/vsp_fill_real_data_5tabs_p1_v1.js\"></script>\n"
                        "<!-- /VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
                    )
                    if "</body>" in html:
                        html = html.replace("</body>", tag + "</body>")
                    elif "</html>" in html:
                        html = html.replace("</html>", tag + "</html>")
                    else:
                        html = html + tag
                    body = html.encode("utf-8")

                    # reset Content-Length
                    headers = [(k,v) for (k,v) in headers if str(k).lower() != "content-length"]
                    headers.append(("Content-Length", str(len(body))))
            except Exception:
                pass

        start_response(captured["status"] or "200 OK", headers, captured["exc"])
        return [body]
# === /VSP_GATEWAY_INJECT_FILLREAL_WSGI_MW_P1_V4 ===
'''
    s = s + "\n\n" + mw + "\n"

tail = r'''
# === VSP_GATEWAY_FORCE_FILLREAL_TAIL_P1_V4 ===
try:
    # FORCE LAST WRAP: must be after all other `application = ...` wrappers
    application = _VspHtmlInjectMw(application)
except Exception:
    pass
# === /VSP_GATEWAY_FORCE_FILLREAL_TAIL_P1_V4 ===
'''
s = s + "\n" + tail + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended tail force wrap:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
