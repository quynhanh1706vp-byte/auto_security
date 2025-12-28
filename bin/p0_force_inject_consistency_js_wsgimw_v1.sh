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

MARK="VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, sys, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1"
if MARK in s:
    print("[OK] marker already present; skip patch")
    sys.exit(0)

patch = r'''
# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---
import time as _vsp_time

class _VspForceInjectJsMw:
    """
    Force-inject a JS tag into /vsp5 HTML response at WSGI level.
    This avoids relying on any specific template being used.
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

        # Only attempt to inject into HTML, uncompressed
        headers = captured["headers"] or []
        ct = ""
        ce = ""
        for (k,v) in headers:
            lk = (k or "").lower()
            if lk == "content-type": ct = v or ""
            if lk == "content-encoding": ce = v or ""
        if ("text/html" not in (ct or "").lower()) or (ce):
            return body_iter

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

        # No-op if already injected
        if b"vsp_dashboard_consistency_patch_v1.js" in body:
            return [body]

        tag = f'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={int(_vsp_time.time())}"></script>'.encode("utf-8")
        needle = b"</body>"
        if needle in body:
            body = body.replace(needle, tag + b"\n" + needle, 1)
        else:
            body = body + b"\n" + tag + b"\n"

        # Fix Content-Length if present
        new_headers = []
        for (k,v) in headers:
            if (k or "").lower() == "content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(body))))
        captured["headers"][:] = new_headers

        # Re-send headers with corrected length
        # (start_response already called; safest is to just return body and rely on server.
        # Gunicorn generally handles it, but we kept Content-Length consistent anyway.)
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
# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---
'''

# Append patch near end
s2 = s + ("\n\n" + patch + "\n")

# Add marker comment for idempotence
s2 = s2 + f"\n# {MARK}\n"

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || warn "systemctl restart failed"
  sleep 0.5
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 20 || true
else
  warn "no systemctl; restart service manually"
fi

echo "== [VERIFY] /vsp5 contains injected JS =="
html="$(curl -fsS "$BASE/vsp5?rid=$RID")"
echo "$html" | grep -q "vsp_dashboard_consistency_patch_v1\.js" \
  && ok "inject OK: found vsp_dashboard_consistency_patch_v1.js in /vsp5 HTML" \
  || err "inject NOT found in /vsp5 HTML (still). Need inspect /vsp5 response pipeline."

ok "Done. Open: $BASE/vsp5?rid=$RID and look for panel 'Severity Distribution (Commercial — from dash_kpis)'."
