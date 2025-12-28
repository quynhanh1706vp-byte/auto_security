#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p2_eof_${TS}"
echo "[BACKUP] ${W}.bak_p2_eof_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_INJECT_BUNDLE_TABS5_EOF_V1D"
if MARK in s:
    print("[OK] already has:", MARK)
else:
    block = f"""

# ===================== {MARK} =====================
# Register bundle injector on FINAL exported WSGI app (application/app) at EOF.
try:
    import re as _re
    import time as _time
    from flask import request as _request

    _VSP_P2_BUNDLE_FALLBACK_V_EOF = str(int(_time.time()))

    def _vsp_p2_inject_bundle_tabs5_impl(resp):
        try:
            path = getattr(_request, "path", "") or ""
            if path == "/":
                path = "/vsp5"
            if path not in ("/vsp5","/runs","/settings","/data_source","/rule_overrides"):
                return resp

            try:
                if hasattr(resp, "direct_passthrough") and getattr(resp, "direct_passthrough", False):
                    resp.direct_passthrough = False
            except Exception:
                pass

            ct = (resp.headers.get("Content-Type","") or "").lower()
            mt = (getattr(resp, "mimetype", "") or "").lower()
            if ("text/html" not in ct) and (mt != "text/html"):
                return resp

            body = resp.get_data(as_text=True)  # type: ignore
            mm = _re.search(r'vsp_tabs4_autorid_v1\\.js\\?v=([0-9]{{6,}})', body)
            v = mm.group(1) if mm else _VSP_P2_BUNDLE_FALLBACK_V_EOF

            if "vsp_bundle_tabs5_v1.js" in body:
                try: resp.headers["X-VSP-P2-BUNDLE"] = "present"
                except Exception: pass
                return resp

            tag = f'<script defer src="/static/js/vsp_bundle_tabs5_v1.js?v={{v}}"></script>'

            if "</body>" in body:
                body = body.replace("</body>", tag + "\\\\n</body>", 1)
            elif "</head>" in body:
                body = body.replace("</head>", tag + "\\\\n</head>", 1)
            else:
                body = body + "\\\\n" + tag + "\\\\n"

            resp.set_data(body)  # type: ignore
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            try: resp.headers["X-VSP-P2-BUNDLE"] = "injected"
            except Exception: pass
            return resp
        except Exception:
            try: resp.headers["X-VSP-P2-BUNDLE"] = "err"
            except Exception: pass
            return resp

    _final_app = globals().get("application") or globals().get("app")
    if _final_app is not None and hasattr(_final_app, "after_request"):
        @_final_app.after_request
        def _vsp_p2_inject_bundle_tabs5_after(resp):
            return _vsp_p2_inject_bundle_tabs5_impl(resp)
except Exception:
    pass
# ===================== /{MARK} =====================

""".rstrip() + "\n"
    p.write_text(s + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] wsgi compiles")
PY

echo "== restart =="
systemctl restart "$SVC"
systemctl --no-pager --full status "$SVC" | sed -n '1,12p'

echo "== [SELF-CHECK] /vsp5 header + bundle =="
curl -fsS -I "$BASE/vsp5" | egrep -i 'HTTP/|Server|Content-Type|Content-Length|X-VSP-P2-BUNDLE' || true
H="$(curl -fsS "$BASE/vsp5")"
echo "$H" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on /vsp5"; exit 3; }
echo "[OK] bundle present on /vsp5"
