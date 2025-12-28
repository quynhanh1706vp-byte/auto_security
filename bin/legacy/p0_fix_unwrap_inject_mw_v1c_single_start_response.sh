#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251219_092640}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_unwrapmw_v1c_${TS}"
ok "backup: ${WSGI}.bak_unwrapmw_v1c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

# Remove old V1B block if present
s2 = re.sub(
    r"\n# --- VSP_P0_RFA_UNWRAP_INJECT_V1B ---.*?# VSP_P0_RFA_UNWRAP_INJECT_V1B\n",
    "\n",
    s,
    flags=re.DOTALL
)

MARK="VSP_P0_RFA_UNWRAP_INJECT_V1C"
if MARK in s2:
    print("[OK] V1C already present")
    p.write_text(s2, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

mw = r'''
# --- VSP_P0_RFA_UNWRAP_INJECT_V1C ---
import gzip as _vsp_gzip_u1c
import time as _vsp_time_u1c

class _VspInjectRfaUnwrapMwV1C:
    """
    Single start_response: capture status/headers from downstream, inject, then call start_response once.
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        if (environ.get("PATH_INFO") or "") != "/vsp5":
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None, "exc_info": None}
        wrote = []

        def _write(data: bytes):
            if data:
                wrote.append(data)

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc_info"] = exc_info
            # return write callable per WSGI spec
            return _write

        resp_iter = self.app(environ, _sr)

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        exc_info = captured["exc_info"]

        # If app used write(), include it
        body = b"".join(wrote) + b"".join(resp_iter)

        ctype = ""
        enc = ""
        for k,v in headers:
            lk = (k or "").lower()
            if lk == "content-type": ctype = v or ""
            if lk == "content-encoding": enc = (v or "").lower()

        if "text/html" not in (ctype or ""):
            # pass-through, but ensure Content-Length consistent if present
            new=[]
            for k,v in headers:
                if (k or "").lower()=="content-length":
                    continue
                new.append((k,v))
            new.append(("Content-Length", str(len(body))))
            start_response(status, new, exc_info)
            return [body]

        # decompress if gzip
        raw = body
        try:
            if enc == "gzip":
                raw = _vsp_gzip_u1c.decompress(body)
        except Exception:
            raw = body

        tag = (f'<script src="/static/js/vsp_rfa_unwrap_v1.js?v={int(_vsp_time_u1c.time())}"></script>\n').encode("utf-8")
        if b"vsp_rfa_unwrap_v1.js" not in raw:
            if b"</head>" in raw:
                raw = raw.replace(b"</head>", tag + b"</head>", 1)
            else:
                raw = tag + raw

        out = raw
        if enc == "gzip":
            out = _vsp_gzip_u1c.compress(raw)

        new=[]
        for k,v in headers:
            lk=(k or "").lower()
            if lk in ("content-length",):
                continue
            new.append((k,v))
        # commercial: no-store
        if not any((k or "").lower()=="cache-control" for k,_ in new):
            new.append(("Cache-Control","no-store"))
        new.append(("Content-Length", str(len(out))))
        start_response(status, new, exc_info)
        return [out]

try:
    application = _VspInjectRfaUnwrapMwV1C(application)
except Exception:
    pass
# --- /VSP_P0_RFA_UNWRAP_INJECT_V1C ---
# VSP_P0_RFA_UNWRAP_INJECT_V1C
'''
s2 = s2.rstrip() + "\n\n" + mw + "\n"
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] installed V1C MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.8
fi

echo "== [VERIFY] /vsp5 200 + unwrap injected (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -n "vsp_rfa_unwrap_v1.js" | head -n 3
ok "DONE"
