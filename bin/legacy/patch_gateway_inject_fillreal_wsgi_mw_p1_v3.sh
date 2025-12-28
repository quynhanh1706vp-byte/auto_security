#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fillreal_wsgi_${TS}"
echo "[BACKUP] ${F}.bak_fillreal_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_GATEWAY_INJECT_FILLREAL_WSGI_MW_P1_V3"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

mw = r'''
# === VSP_GATEWAY_INJECT_FILLREAL_WSGI_MW_P1_V3 ===
import re as _re

class _VspHtmlInjectMw:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        captured = {"status": None, "headers": None, "exc": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            captured["exc"] = exc_info
            # delay calling real start_response until we possibly rewrite body
            return None

        app_iter = self.app(environ, _sr)

        try:
            body_chunks = []
            for chunk in app_iter:
                if chunk:
                    body_chunks.append(chunk)
            body = b"".join(body_chunks)
        finally:
            try:
                close = getattr(app_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = captured["headers"] or []
        ct = ""
        for (k,v) in headers:
            if str(k).lower() == "content-type":
                ct = str(v).lower()
                break

        # only touch HTML
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

                    # drop Content-Length (recomputed)
                    headers = [(k,v) for (k,v) in headers if str(k).lower() != "content-length"]
                    headers.append(("Content-Length", str(len(body))))
            except Exception:
                pass

        # now start response
        start_response(captured["status"] or "200 OK", headers, captured["exc"])
        return [body]
# === /VSP_GATEWAY_INJECT_FILLREAL_WSGI_MW_P1_V3 ===
'''

# Insert middleware near end, then wrap `application` if present
# Place before last occurrence of "application =" if possible
m = re.search(r"^application\s*=\s*", s, flags=re.M)
if m:
    ins_at = m.start()
    s2 = s[:ins_at] + mw + "\n" + s[ins_at:]
else:
    s2 = s + "\n\n" + mw + "\n"

# Wrap application safely (idempotent check by marker string)
wrap = r'''
# === VSP_GATEWAY_WRAP_APPLICATION_WITH_FILLREAL_P1_V3 ===
try:
    _vsp_inner = globals().get("application") or globals().get("app")
    if _vsp_inner is not None and not isinstance(_vsp_inner, _VspHtmlInjectMw):
        application = _VspHtmlInjectMw(_vsp_inner)
except Exception:
    pass
# === /VSP_GATEWAY_WRAP_APPLICATION_WITH_FILLREAL_P1_V3 ===
'''

if "VSP_GATEWAY_WRAP_APPLICATION_WITH_FILLREAL_P1_V3" not in s2:
    s2 = s2 + "\n" + wrap + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart UI:"
echo "  sudo systemctl restart vsp-ui-8910.service"
