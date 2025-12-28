#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

JS="static/js/vsp_rid_persist_patch_v1.js"
MARK="VSP_P0_PERSIST_RID_LOCALSTORAGE_V1"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

mkdir -p static/js

cat > "$JS" <<'JS'
/* VSP_P0_PERSIST_RID_LOCALSTORAGE_V1 */
(function(){
  'use strict';

  const KEY = 'vsp_rid_last';

  function detectRidSelect(){
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = document.querySelector(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    // fallback: a SELECT whose options look like VSP_...
    const sels = Array.from(document.querySelectorAll('select'));
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getRidFromUrl(){
    const u = new URL(window.location.href);
    return u.searchParams.get('rid') || '';
  }

  function setRidInUrl(rid){
    const u = new URL(window.location.href);
    u.searchParams.set('rid', rid);
    // keep path /vsp5 stable
    const target = u.toString();
    if (target !== window.location.href){
      window.history.replaceState({}, '', target);
    }
  }

  function boot(){
    try{
      const urlRid = getRidFromUrl();
      const saved  = localStorage.getItem(KEY) || '';

      // If no rid in URL but we have saved rid, redirect once to ensure server-side data uses rid consistently
      if (!urlRid && saved && (location.pathname === '/vsp5' || location.pathname.startsWith('/vsp5'))){
        const u = new URL(window.location.href);
        u.searchParams.set('rid', saved);
        window.location.replace(u.toString());
        return;
      }

      // Sync select + persist on change
      const sel = detectRidSelect();
      if (sel){
        // On load, if URL rid exists, persist it
        const current = urlRid || sel.value || '';
        if (current) localStorage.setItem(KEY, current);

        if (!sel.__vspPersistBound){
          sel.__vspPersistBound = true;
          sel.addEventListener('change', ()=>{
            const rid = sel.value || '';
            if (rid){
              localStorage.setItem(KEY, rid);
              setRidInUrl(rid);
            }
          }, {passive:true});
        }
      } else {
        // even if no select, still persist URL rid
        if (urlRid) localStorage.setItem(KEY, urlRid);
      }
    }catch(_e){}
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
JS

ok "wrote $JS"

# Inject this JS via the same WSGI pipeline already working: simplest is to append to HTML by WSGI.
# We'll patch wsgi_vsp_ui_gateway.py to inject this second tag into /vsp5 as well.
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || err "missing $WSGI"

cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_PERSIST_RID_LOCALSTORAGE_V1"

if MARK in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# We already have a working MW that injects vsp_dashboard_consistency_patch_v1.js.
# Add a second injection by modifying that MW: easiest safe approach is to inject both tags by changing
# the string 'tag =' into building two tags.
rx = re.compile(r'tag\s*=\s*f[\'"]<script src="/static/js/vsp_dashboard_consistency_patch_v1\.js\?v=\{int\(_vsp_time\.time\(\)\)\}"></script>[\'"]\.encode\("utf-8"\)', re.M)
if not rx.search(s):
    print("[WARN] could not locate consistency tag assignment; will append a tiny helper MW instead")

    helper = r'''
# --- VSP_P0_PERSIST_RID_LOCALSTORAGE_V1 ---
import time as _vsp_time2

class _VspForceInjectRidPersistMw:
    def __init__(self, app): self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured={"status":None,"headers":None,"exc":None}
        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=list(headers or [])
            captured["exc"]=exc_info
            return (lambda _x: None)

        it = self.app(environ, _sr)
        hdrs=captured["headers"] or []
        st=captured["status"] or "200 OK"
        exc=captured["exc"]

        ct=""; ce=""
        for (k,v) in hdrs:
            lk=(k or "").lower()
            if lk=="content-type": ct=v or ""
            if lk=="content-encoding": ce=(v or "").lower()

        if "text/html" not in (ct or "").lower():
            start_response(st, hdrs, exc)
            return it
        if ce:
            # if encoded, just return (we already have consistency MW handling gzip)
            start_response(st, hdrs, exc)
            return it

        chunks=[]
        try:
            for c in it:
                if c: chunks.append(c if isinstance(c,(bytes,bytearray)) else str(c).encode("utf-8","ignore"))
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass
        body=b"".join(chunks)

        if b"vsp_rid_persist_patch_v1.js" in body:
            new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
            new_hdrs.append(("Content-Length", str(len(body))))
            start_response(st, new_hdrs, exc)
            return [body]

        tag=f'<script src="/static/js/vsp_rid_persist_patch_v1.js?v={int(_vsp_time2.time())}"></script>'.encode("utf-8")
        needle=b"</body>"
        if needle in body:
            body=body.replace(needle, tag+b"\n"+needle, 1)
        else:
            body=body+b"\n"+tag+b"\n"

        new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
        new_hdrs.append(("Content-Length", str(len(body))))
        start_response(st, new_hdrs, exc)
        return [body]

try:
    application = _VspForceInjectRidPersistMw(application)
except Exception:
    pass
# --- /VSP_P0_PERSIST_RID_LOCALSTORAGE_V1 ---
'''
    s = s.rstrip() + "\n\n" + helper + "\n# " + MARK + "\n"
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] appended helper MW for rid persist")
    raise SystemExit(0)

# Replace single-tag with dual-tag (consistency + persist)
ts = int(time.time())
dual = f'tag = (f\'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={{int(_vsp_time.time())}}"></script>\\n\'\n' \
       f'       f\'<script src="/static/js/vsp_rid_persist_patch_v1.js?v={ts}"></script>\').encode("utf-8")'
s = rx.sub(dual, s, count=1)
s = s + f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] modified existing MW to inject rid persist too")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.6
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 15 || true
else
  warn "no systemctl; restart manually"
fi

echo "== [VERIFY] /vsp5 contains rid persist JS =="
curl -fsS --compressed "$BASE/vsp5" | grep -q "vsp_rid_persist_patch_v1\.js" \
  && ok "inject OK: found vsp_rid_persist_patch_v1.js" \
  || err "inject NOT found"

ok "DONE. Behavior: open /vsp5 without rid => it will redirect to last rid; changing RID updates URL + localStorage."
