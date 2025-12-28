#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${1:-VSP_CI_20251215_173713}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

MARK="VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace the V1 block if present, else append V2 block
re_v1 = re.compile(r"# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---.*?# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---\s*", re.S)

v2_block = r'''
# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP ---
import time as _vsp_time
import gzip as _vsp_gzip
from io import BytesIO as _VspBytesIO

class _VspForceInjectJsMw:
    """
    Force-inject a JS tag into /vsp5 HTML response at WSGI level.
    Supports gzip Content-Encoding (decompress -> inject -> recompress).
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            return start_response(status, headers, exc_info)

        body_iter = self.app(environ, _sr)

        headers = captured["headers"] or []
        ct = ""
        ce = ""
        for (k,v) in headers:
            lk = (k or "").lower()
            if lk == "content-type": ct = v or ""
            if lk == "content-encoding": ce = (v or "").lower()

        # Only inject into HTML
        if "text/html" not in (ct or "").lower():
            return body_iter

        # collect body
        try:
            chunks = []
            for c in body_iter:
                if c:
                    chunks.append(c if isinstance(c, (bytes, bytearray)) else str(c).encode("utf-8", "ignore"))
            body = b"".join(chunks)
        finally:
            try:
                close = getattr(body_iter, "close", None)
                if callable(close): close()
            except Exception:
                pass

        # If gzip: decompress for inspection/injection
        was_gzip = ("gzip" in ce)
        if was_gzip:
            try:
                body = _vsp_gzip.decompress(body)
            except Exception:
                # If cannot decompress, skip injection safely
                return [body] if isinstance(body, (bytes, bytearray)) else [bytes(body)]

        # already injected?
        if b"vsp_dashboard_consistency_patch_v1.js" in body:
            if was_gzip:
                body = _vsp_gzip.compress(body)
            return [body]

        tag = f'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={int(_vsp_time.time())}"></script>'.encode("utf-8")
        needle = b"</body>"
        if needle in body:
            body = body.replace(needle, tag + b"\n" + needle, 1)
        else:
            body = body + b"\n" + tag + b"\n"

        # recompress if needed
        if was_gzip:
            body = _vsp_gzip.compress(body)

        # Fix Content-Length
        new_headers = []
        for (k,v) in headers:
            if (k or "").lower() == "content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(body))))
        captured["headers"][:] = new_headers

        return [body]

# Wrap exported WSGI callable if present
try:
    application = _VspForceInjectJsMw(application)
except Exception:
    try:
        app  # noqa
        application = _VspForceInjectJsMw(app)
    except Exception:
        pass
# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP ---
'''

if "VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP" in s:
    print("[OK] V2 marker already present; skip")
    sys.exit(0)

if re_v1.search(s):
    s = re_v1.sub(v2_block + "\n", s)
    s = s + "\n# VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP\n"
    print("[OK] replaced V1 block => V2 gzip-capable")
else:
    s = s + "\n\n" + v2_block + "\n# VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP\n"
    print("[OK] appended V2 gzip-capable block")

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || warn "systemctl restart failed"
  sleep 0.6
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 15 || true
else
  warn "no systemctl; restart service manually"
fi

echo "== [VERIFY headers] =="
curl -sSI "$BASE/vsp5?rid=$RID" | egrep -i 'content-type|content-encoding|vary|cache' || true

echo "== [VERIFY] /vsp5 contains injected JS (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -q "vsp_dashboard_consistency_patch_v1\.js" \
  && ok "inject OK: found vsp_dashboard_consistency_patch_v1.js in /vsp5 HTML" \
  || err "inject NOT found in /vsp5 HTML even with --compressed"

ok "Done. Open: $BASE/vsp5?rid=$RID and look for panel 'Severity Distribution (Commercial — from dash_kpis)'."
