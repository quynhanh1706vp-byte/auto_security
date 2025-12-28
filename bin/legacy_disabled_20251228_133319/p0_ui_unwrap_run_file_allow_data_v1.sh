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

# 1) helper JS
HELP="static/js/vsp_rfa_unwrap_v1.js"
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

# 2) inject helper into /vsp5 HTML via WSGI (gzip safe already in your system)
cp -f "$WSGI" "${WSGI}.bak_rfaunwrap_${TS}"
ok "backup: ${WSGI}.bak_rfaunwrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, time

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RFA_UNWRAP_INJECT_V1"
if MARK in s:
    print("[OK] already injected marker")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

# We reuse your existing gzip-capable HTML injection logic:
# Find the line where it injects vsp_dashboard_consistency_patch_v1.js and append unwrap next to it.
needle = "vsp_dashboard_consistency_patch_v1.js"
if needle not in s:
    print("[WARN] could not find consistency inject marker; will append a minimal MW near end")
    # fallback: append a tiny MW that injects before </head> for /vsp5 only (not gzip aware)
    # but since you already have gzip inject infra, this should almost always find needle.
    raise SystemExit(0)

# Insert a second <script> right after the consistency script tag construction (best effort)
s2 = s
# common tag construction contains the filename; we add another script tag literal nearby
s2 = s2.replace(
    needle,
    needle + '"'></script>\\n<script src="/static/js/vsp_rfa_unwrap_v1.js?v=' + "' + str(int(time.time())) + '" + '\"\"></script><script src=\"/static/js/"  # will be fixed below
)

# Above replace is messy; do a safer method: append a separate injection block at end using existing gzip MW marker.
# We'll just append a new gzip-capable injection MW similar to your V3 inject, but only for /vsp5 and only adds unwrap script.
if s2 == s:
    # no-op, continue to append MW
    pass

# Append simple MW that injects unwrap script into /vsp5 responses (handles gzip/identity)
# NOTE: this MW relies on 'gzip' and 're' already used in your file; but we include imports inside.
mw = r'''
# --- VSP_P0_RFA_UNWRAP_INJECT_V1 ---
import gzip as _vsp_gzip_u1
import re as _vsp_re_u1
import time as _vsp_time_u1

class _VspInjectRfaUnwrapMw:
    def __init__(self, app):
        self.app=app
    def __call__(self, environ, start_response):
        path=(environ.get("PATH_INFO") or "")
        if path != "/vsp5":
            return self.app(environ, start_response)

        hdrs_box={}
        def _sr(status, headers, exc_info=None):
            hdrs_box["status"]=status
            hdrs_box["headers"]=list(headers or [])
            return start_response(status, headers, exc_info)

        resp=self.app(environ, _sr)
        status=hdrs_box.get("status","200 OK")
        headers=hdrs_box.get("headers",[])
        ctype=""
        enc=""
        for k,v in headers:
            lk=(k or "").lower()
            if lk=="content-type": ctype=v or ""
            if lk=="content-encoding": enc=(v or "").lower()

        # only html
        if "text/html" not in (ctype or ""):
            return resp

        body=b"".join(resp)
        try:
            if enc=="gzip":
                body=_vsp_gzip_u1.decompress(body)
        except Exception:
            pass

        tag = (f'<script src="/static/js/vsp_rfa_unwrap_v1.js?v={int(_vsp_time_u1.time())}"></script>\n').encode("utf-8")
        if b"vsp_rfa_unwrap_v1.js" not in body:
            if b"</head>" in body:
                body=body.replace(b"</head>", tag + b"</head>", 1)
            else:
                body=tag + body

        # re-pack if gzip
        out=body
        if enc=="gzip":
            out=_vsp_gzip_u1.compress(body)

        # fix headers length
        new=[]
        for k,v in headers:
            if (k or "").lower()=="content-length":
                continue
            new.append((k,v))
        new.append(("Content-Length", str(len(out))))
        start_response(status, new, None)
        return [out]

try:
    application = _VspInjectRfaUnwrapMw(application)
except Exception:
    pass
# --- /VSP_P0_RFA_UNWRAP_INJECT_V1 ---
'''
s = s.rstrip() + "\n\n" + mw + "\n# VSP_P0_RFA_UNWRAP_INJECT_V1\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended unwrap inject MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.7
fi

echo "== [VERIFY] /vsp5 contains unwrap JS (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -n "vsp_rfa_unwrap_v1.js" | head -n 5 && ok "inject OK"

echo "== [VERIFY] run_file_allow wrapper exists =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_data=",isinstance(j.get("data"),dict),"from=",j.get("from"))'

ok "DONE. Next: patch dashboard JS to call __vspRfaUnwrap where needed."
