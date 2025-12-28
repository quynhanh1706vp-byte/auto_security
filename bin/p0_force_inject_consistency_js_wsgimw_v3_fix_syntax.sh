#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${1:-VSP_CI_20251215_173713}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

# 1) Restore latest backup (prefer V2 backup, else V1 backup)
bak=""
bak="$(ls -1t ${WSGI}.bak_VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  bak="$(ls -1t ${WSGI}.bak_VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1_* 2>/dev/null | head -n 1 || true)"
fi
[ -n "$bak" ] || err "cannot find backup for restore (expected ${WSGI}.bak_*_V1/V2...)"

cp -f "$bak" "$WSGI"
ok "restored from backup: $bak -> $WSGI"

# 2) Patch V3 safely (remove any old V1/V2 blocks by slicing, then append V3)
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_before_v3_${TS}"
ok "backup: ${WSGI}.bak_before_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Remove any previous injected blocks (V1/V2) by pattern slicing
blocks = [
    (re.compile(r"# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---.*?# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V1 ---\s*", re.S), "V1"),
    (re.compile(r"# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP ---.*?# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V2_GZIP ---\s*", re.S), "V2"),
]

removed = []
for rx, name in blocks:
    m = rx.search(s)
    if m:
        s = s[:m.start()] + s[m.end():]
        removed.append(name)

v3_marker = "VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V3_GZIP_SAFE"
if v3_marker in s:
    print("[OK] V3 marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

v3 = r'''
# --- VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V3_GZIP_SAFE ---
import time as _vsp_time
import gzip as _vsp_gzip

class _VspForceInjectJsMw:
    """
    Force-inject JS tag into /vsp5 HTML at WSGI level.
    - Works with gzip (decompress -> inject -> recompress)
    - Delays start_response until after body modification (correct headers/length)
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            # Return a dummy write callable
            return (lambda _x: None)

        body_iter = self.app(environ, _sr)

        headers = captured["headers"] or []
        status  = captured["status"] or "200 OK"
        exc     = captured["exc"]

        # Collect headers
        ct = ""
        ce = ""
        for (k, v) in headers:
            lk = (k or "").lower()
            if lk == "content-type": ct = v or ""
            if lk == "content-encoding": ce = (v or "").lower()

        # Only inject HTML
        if "text/html" not in (ct or "").lower():
            start_response(status, headers, exc)
            return body_iter

        # Collect body
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

        was_gzip = ("gzip" in ce)
        if was_gzip:
            try:
                body = _vsp_gzip.decompress(body)
            except Exception:
                # Can't decompress => return original safely
                start_response(status, headers, exc)
                return [body]

        # If already injected, just return
        if b"vsp_dashboard_consistency_patch_v1.js" in body:
            if was_gzip:
                body = _vsp_gzip.compress(body)
            # Ensure Content-Length correctness
            new_headers = [(k,v) for (k,v) in headers if (k or "").lower() != "content-length"]
            new_headers.append(("Content-Length", str(len(body))))
            start_response(status, new_headers, exc)
            return [body]

        tag = f'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={int(_vsp_time.time())}"></script>'.encode("utf-8")
        needle = b"</body>"
        if needle in body:
            body = body.replace(needle, tag + b"\n" + needle, 1)
        else:
            body = body + b"\n" + tag + b"\n"

        if was_gzip:
            body = _vsp_gzip.compress(body)

        # Rebuild headers with correct length, keep Content-Encoding as-is
        new_headers = [(k,v) for (k,v) in headers if (k or "").lower() != "content-length"]
        new_headers.append(("Content-Length", str(len(body))))
        start_response(status, new_headers, exc)
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
# --- /VSP_P0_FORCE_INJECT_CONSISTENCY_JS_WSGIMW_V3_GZIP_SAFE ---
'''

s = s.rstrip() + "\n\n" + v3 + "\n# " + v3_marker + "\n"
p.write_text(s, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched V3; removed old:", removed)
PY

# 3) Restart service
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.6
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 18 || true
else
  warn "no systemctl; restart service manually"
fi

echo "== [VERIFY headers] =="
curl -sSI "$BASE/vsp5?rid=$RID" | egrep -i 'content-type|content-encoding|vary|cache' || true

echo "== [VERIFY] injected JS present in HTML (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -q "vsp_dashboard_consistency_patch_v1\.js" \
  && ok "inject OK: found vsp_dashboard_consistency_patch_v1.js in /vsp5 HTML" \
  || err "inject NOT found in /vsp5 HTML even with --compressed"

echo "== [VERIFY] static JS reachable =="
curl -sS -I "$BASE/static/js/vsp_dashboard_consistency_patch_v1.js" | head -n 5 || true

ok "DONE. Open: $BASE/vsp5?rid=$RID and check panel 'Severity Distribution (Commercial — from dash_kpis)'."
