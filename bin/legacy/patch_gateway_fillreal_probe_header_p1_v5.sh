#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fillreal_probe_${TS}"
echo "[BACKUP] ${F}.bak_fillreal_probe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_GATEWAY_FILLREAL_PROBE_HEADER_P1_V5"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

blk = r'''
# === VSP_GATEWAY_FILLREAL_PROBE_HEADER_P1_V5 ===
import re as _re

class _VspFillRealProbeMWP1V5:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        captured = {"status": None, "headers": None, "exc": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # return write callable
            def _write(_data): return None
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
        # always add probe header
        headers = [(k,v) for (k,v) in headers if str(k).lower() != "x-vsp-fillreal"]
        headers.append(("X-VSP-FILLREAL", "P1_V5"))

        # sniff headers
        ct = ""
        ce = ""
        for (k,v) in headers:
            lk = str(k).lower()
            if lk == "content-type": ct = str(v).lower()
            if lk == "content-encoding": ce = str(v).lower()

        # only inject into plain html (skip gzip/br)
        if "text/html" in ct and body and (not ce or ("gzip" not in ce and "br" not in ce)):
            try:
                html = body.decode("utf-8", errors="replace")
                if ("vsp_fill_real_data_5tabs_p1_v1.js" not in html) and ("VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" not in html):
                    tag = (
                        "\n<!-- VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
                        "<script src=\"/static/js/vsp_fill_real_data_5tabs_p1_v1.js\"></script>\n"
                        "<!-- /VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY -->\n"
                    )
                    # case-insensitive insert before </body> or </html>
                    if _re.search(r"</body\s*>", html, flags=_re.I):
                        html = _re.sub(r"</body\s*>", tag + "</body>", html, count=1, flags=_re.I)
                    elif _re.search(r"</html\s*>", html, flags=_re.I):
                        html = _re.sub(r"</html\s*>", tag + "</html>", html, count=1, flags=_re.I)
                    else:
                        html = html + tag
                    body = html.encode("utf-8")

                    # fix content-length
                    headers = [(k,v) for (k,v) in headers if str(k).lower() != "content-length"]
                    headers.append(("Content-Length", str(len(body))))
            except Exception:
                pass

        start_response(captured["status"] or "200 OK", headers, captured["exc"])
        return [body]
# === /VSP_GATEWAY_FILLREAL_PROBE_HEADER_P1_V5 ===

# force last wrap
try:
    application = _VspFillRealProbeMWP1V5(application)
except Exception:
    pass
'''
s2 = s + "\n\n" + blk + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
