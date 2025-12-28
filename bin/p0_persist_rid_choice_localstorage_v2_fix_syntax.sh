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

# 0) Ensure JS file exists (your script already created it, but keep safe)
JS="static/js/vsp_rid_persist_patch_v1.js"
mkdir -p static/js
if [ ! -s "$JS" ]; then
  warn "missing $JS, recreating minimal persist logic"
  cat > "$JS" <<'JS'
/* VSP_P0_PERSIST_RID_LOCALSTORAGE_V2_MIN */
(function(){
  'use strict';
  const KEY='vsp_rid_last';
  function ridFromUrl(){ try{ return (new URL(location.href)).searchParams.get('rid')||''; }catch(_e){ return ''; } }
  function pickSelect(){
    const ids=['#rid','#RID','#vsp-rid','#vsp-rid-select','#ridSelect','#runRid','#run-rid'];
    for(const id of ids){ const el=document.querySelector(id); if(el && el.tagName==='SELECT') return el; }
    const sels=[...document.querySelectorAll('select')];
    for(const s of sels){
      const opts=[...(s.options||[])];
      if(opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }
  function setUrlRid(rid){
    try{
      const u=new URL(location.href);
      u.searchParams.set('rid', rid);
      history.replaceState({},'',u.toString());
    }catch(_e){}
  }
  function boot(){
    try{
      const urlRid=ridFromUrl();
      const saved=localStorage.getItem(KEY)||'';
      if(!urlRid && saved && (location.pathname==='/vsp5' || location.pathname.startsWith('/vsp5'))){
        const u=new URL(location.href); u.searchParams.set('rid', saved);
        location.replace(u.toString()); return;
      }
      const sel=pickSelect();
      const cur=(urlRid || (sel?sel.value:'') || '').trim();
      if(cur) localStorage.setItem(KEY, cur);
      if(sel && !sel.__persistBound){
        sel.__persistBound=true;
        sel.addEventListener('change', ()=>{
          const r=(sel.value||'').trim();
          if(r){ localStorage.setItem(KEY,r); setUrlRid(r); }
        }, {passive:true});
      }
    }catch(_e){}
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
JS
fi
ok "js ok: $JS"

# 1) Restore from the backup created right before the broken patch
bak="$(ls -1t ${WSGI}.bak_VSP_P0_PERSIST_RID_LOCALSTORAGE_V1_* 2>/dev/null | head -n 1 || true)"
[ -n "$bak" ] || err "cannot find backup ${WSGI}.bak_VSP_P0_PERSIST_RID_LOCALSTORAGE_V1_* to restore"

cp -f "$bak" "$WSGI"
ok "restored: $bak -> $WSGI"

# 2) Append a separate gzip-safe MW to inject vsp_rid_persist_patch_v1.js into /vsp5
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_before_ridmw_${TS}"
ok "backup: ${WSGI}.bak_before_ridmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_P0_PERSIST_RID_LOCALSTORAGE_V2_MW_GZIP"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = r'''
# --- VSP_P0_PERSIST_RID_LOCALSTORAGE_V2_MW_GZIP ---
import time as _vsp_time_rid
import gzip as _vsp_gzip_rid

class _VspForceInjectRidPersistMw:
    """
    Inject vsp_rid_persist_patch_v1.js into /vsp5 HTML at WSGI level (gzip-safe).
    Kept separate to avoid touching existing MWs.
    """
    def __init__(self, app):
        self.app = app

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
        hdrs = captured["headers"] or []
        st   = captured["status"] or "200 OK"
        exc  = captured["exc"]

        ct=""; ce=""
        for (k,v) in hdrs:
            lk=(k or "").lower()
            if lk=="content-type": ct=v or ""
            if lk=="content-encoding": ce=(v or "").lower()

        if "text/html" not in (ct or "").lower():
            start_response(st, hdrs, exc)
            return it

        # collect body
        try:
            chunks=[]
            for c in it:
                if c:
                    chunks.append(c if isinstance(c,(bytes,bytearray)) else str(c).encode("utf-8","ignore"))
            body=b"".join(chunks)
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass

        was_gzip = ("gzip" in ce)
        if was_gzip:
            try:
                body=_vsp_gzip_rid.decompress(body)
            except Exception:
                start_response(st, hdrs, exc)
                return [body]

        if b"vsp_rid_persist_patch_v1.js" in body:
            if was_gzip:
                body=_vsp_gzip_rid.compress(body)
            new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
            new_hdrs.append(("Content-Length", str(len(body))))
            start_response(st, new_hdrs, exc)
            return [body]

        tag=f'<script src="/static/js/vsp_rid_persist_patch_v1.js?v={int(_vsp_time_rid.time())}"></script>'.encode("utf-8")
        needle=b"</body>"
        if needle in body:
            body=body.replace(needle, tag+b"\n"+needle, 1)
        else:
            body=body+b"\n"+tag+b"\n"

        if was_gzip:
            body=_vsp_gzip_rid.compress(body)

        new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
        new_hdrs.append(("Content-Length", str(len(body))))
        start_response(st, new_hdrs, exc)
        return [body]

try:
    application = _VspForceInjectRidPersistMw(application)
except Exception:
    pass
# --- /VSP_P0_PERSIST_RID_LOCALSTORAGE_V2_MW_GZIP ---
# VSP_P0_PERSIST_RID_LOCALSTORAGE_V2_MW_GZIP
'''

s = s.rstrip() + "\n\n" + block + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended rid persist MW + py_compile OK")
PY

# 3) Restart service
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.6
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 15 || true
else
  warn "no systemctl; restart manually"
fi

echo "== [VERIFY] /vsp5 contains rid persist JS (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -q "vsp_rid_persist_patch_v1\.js" \
  && ok "inject OK: found vsp_rid_persist_patch_v1.js" \
  || err "inject NOT found"

echo "== [VERIFY] static rid persist JS reachable =="
curl -sS -I "$BASE/static/js/vsp_rid_persist_patch_v1.js" | head -n 5 || true

ok "DONE. Behavior: change RID => stored; open /vsp5 without rid => redirects to last rid."
