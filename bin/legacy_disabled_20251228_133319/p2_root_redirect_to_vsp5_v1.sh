#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p2_rootredir_${TS}"
echo "[BACKUP] ${W}.bak_p2_rootredir_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_ROOT_REDIRECT_TO_VSP5_WSGI_V1"
if MARK in s:
    print("[OK] already has:", MARK)
else:
    block = f"""

# ===================== {MARK} =====================
# WSGI middleware: redirect / -> /vsp5 (commercial entry)
try:
    def _vsp_p2_wsgi_mw_root_redirect(app):
        def _wrapped(environ, start_response):
            try:
                path = (environ.get("PATH_INFO") or "") or ""
                # Only root. Do not touch /api, /static, or others.
                if path == "/":
                    qs = environ.get("QUERY_STRING") or ""
                    loc = "/vsp5" + (("?" + qs) if qs else "")
                    status = "302 Found"
                    headers = [
                        ("Location", loc),
                        ("Cache-Control", "no-store"),
                        ("Content-Type", "text/plain; charset=utf-8"),
                        ("Content-Length", "0"),
                        ("X-VSP-ROOT-REDIRECT", "1"),
                    ]
                    start_response(status, headers)
                    return [b""]
            except Exception:
                pass
            return app(environ, start_response)
        return _wrapped

    _orig_app = globals().get("application")
    if callable(_orig_app):
        globals()["_vsp_p2_application_orig_rootredir"] = _orig_app
        globals()["application"] = _vsp_p2_wsgi_mw_root_redirect(_orig_app)
except Exception:
    pass
# ===================== /{MARK} =====================

""".rstrip() + "\n"
    p.write_text(s + block, encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(p), doraise=True)
print("[OK] wsgi compiles")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK] / redirect =="
curl -fsS -I "$BASE/" | sed -n '1,25p' | egrep -i 'HTTP/|Location:|X-VSP-ROOT-REDIRECT|Cache-Control|Content-Type' || true
curl -fsS -I "$BASE/" | grep -qi '^Location: /vsp5' || { echo "[ERR] / not redirected to /vsp5"; exit 3; }

echo "== [SELF-CHECK] /vsp5 still 200 =="
curl -fsS -I "$BASE/vsp5" | sed -n '1,15p' | egrep -i 'HTTP/|Content-Type|X-VSP-P2-BUNDLE' || true
echo "[DONE] P2 root redirect applied"
