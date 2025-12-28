#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251219_092640}"

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || err "missing $WSGI"

TS="$(date +%Y%m%d_%H%M%S)"

# 1) helper JS (idempotent)
HELP="static/js/vsp_rfa_unwrap_v1.js"
mkdir -p static/js
cat > "$HELP" <<'JS'
/* VSP_P0_RFA_UNWRAP_V1 */
(function(){
  function unwrap(j){
    try{
      if(j && j.ok === true && j.data !== undefined) return j.data;
      return j;
    }catch(e){ return j; }
  }
  function ok(j){
    try{ return !!(j && j.ok === true && j.data !== undefined); }catch(e){ return false; }
  }
  window.__vspRfaUnwrap = unwrap;
  window.__vspRfaOk = ok;
})();
JS
ok "wrote $HELP"

# 2) append gzip-capable inject MW to WSGI (safe, no replace games)
cp -f "$WSGI" "${WSGI}.bak_rfaunwrap_fix_${TS}"
ok "backup: ${WSGI}.bak_rfaunwrap_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RFA_UNWRAP_INJECT_V1B"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

mw = r'''
# --- VSP_P0_RFA_UNWRAP_INJECT_V1B ---
import gzip as _vsp_gzip_u1b
import time as _vsp_time_u1b

class _VspInjectRfaUnwrapMwV1B:
    def __init__(self, app):
        self.app=app

    def __call__(self, environ, start_response):
        path=(environ.get("PATH_INFO") or "")
        if path != "/vsp5":
            return self.app(environ, start_response)

        box={}
        def _sr(status, headers, exc_info=None):
            box["status"]=status
            box["headers"]=list(headers or [])
            return start_response(status, headers, exc_info)

        resp=self.app(environ, _sr)
        status=box.get("status","200 OK")
        headers=box.get("headers",[])

        ctype=""
        enc=""
        for k,v in headers:
            lk=(k or "").lower()
            if lk=="content-type": ctype=v or ""
            if lk=="content-encoding": enc=(v or "").lower()

        if "text/html" not in (ctype or ""):
            return resp

        body=b"".join(resp)
        try:
            if enc=="gzip":
                body=_vsp_gzip_u1b.decompress(body)
        except Exception:
            # if cannot decompress, just fall back to raw
            pass

        tag=(f'<script src="/static/js/vsp_rfa_unwrap_v1.js?v={int(_vsp_time_u1b.time())}"></script>\n').encode("utf-8")
        if b"vsp_rfa_unwrap_v1.js" not in body:
            if b"</head>" in body:
                body=body.replace(b"</head>", tag + b"</head>", 1)
            else:
                body=tag + body

        out=body
        if enc=="gzip":
            out=_vsp_gzip_u1b.compress(body)

        new=[]
        for k,v in headers:
            if (k or "").lower()=="content-length":
                continue
            new.append((k,v))
        new.append(("Cache-Control","no-store"))
        new.append(("Content-Length", str(len(out))))
        start_response(status, new, None)
        return [out]

try:
    application=_VspInjectRfaUnwrapMwV1B(application)
except Exception:
    pass
# --- /VSP_P0_RFA_UNWRAP_INJECT_V1B ---
# VSP_P0_RFA_UNWRAP_INJECT_V1B
'''
s = s.rstrip() + "\n\n" + mw + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended unwrap inject MW V1B + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.7
fi

echo "== [VERIFY] /vsp5 contains unwrap JS (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -n "vsp_rfa_unwrap_v1.js" | head -n 5 && ok "inject OK"

echo "== [VERIFY] static unwrap JS reachable =="
curl -fsSI "$BASE/static/js/vsp_rfa_unwrap_v1.js" | head -n 5

ok "DONE"
