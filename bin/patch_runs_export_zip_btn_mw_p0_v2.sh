#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_exportbtn_v2_${TS}"
echo "[BACKUP] ${F}.bak_runs_exportbtn_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# Append at end (safe). Do NOT use f-strings here.
snippet = r'''
# === VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2 ===
class VSPRunsExportZipBtnMWP0V2:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/runs":
            return self.app(environ, start_response)

        meta = {}
        def sr(status, headers, exc_info=None):
            meta["status"] = status
            meta["headers"] = headers
            meta["exc_info"] = exc_info
            return lambda _x: None

        app_iter = self.app(environ, sr)

        body = b""
        try:
            for chunk in app_iter:
                if chunk:
                    body += chunk
        finally:
            try:
                close = getattr(app_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = meta.get("headers") or []
        ct = ""
        for k,v in headers:
            if str(k).lower() == "content-type":
                ct = str(v); break

        # only inject into HTML /runs
        if ("text/html" in ct) and (b"/api/vsp/run_file" in body) and (MARK.encode() not in body):
            js = b"""
<script>
/* VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2 */
(function(){
  'use strict';
  function ridFromHref(href){
    try{
      const u=new URL(href, location.origin);
      if(!u.pathname.includes('/api/vsp/run_file')) return null;
      return u.searchParams.get('run_id');
    }catch(e){return null;}
  }
  function addBtn(a, rid){
    try{
      const row=a.closest('tr')||a.parentElement;
      if(!row) return;
      if(row.querySelector('a[data-vsp-export-zip="1"]')) return;
      const b=document.createElement('a');
      b.textContent='Export ZIP';
      b.href='/api/vsp/export_zip?run_id='+encodeURIComponent(rid);
      b.setAttribute('data-vsp-export-zip','1');
      b.style.marginLeft='8px';
      b.style.textDecoration='none';
      b.style.display='inline-block';
      b.style.padding='7px 10px';
      b.style.borderRadius='10px';
      b.style.fontWeight='800';
      b.style.border='1px solid rgba(90,140,255,.35)';
      b.style.background='rgba(90,140,255,.16)';
      b.style.color='inherit';
      a.insertAdjacentElement('afterend', b);
    }catch(_){}
  }
  function patch(){
    const links=[...document.querySelectorAll('a[href*="/api/vsp/run_file"]')];
    const seen=new Set();
    for(const a of links){
      const rid=ridFromHref(a.getAttribute('href')||'');
      if(!rid) continue;
      const key=rid+'::'+(a.closest('tr')?a.closest('tr').rowIndex:'x');
      if(seen.has(key)) continue;
      seen.add(key);
      addBtn(a,rid);
    }
  }
  patch(); setTimeout(patch,600); setTimeout(patch,1400);
})();
</script>
"""
            if b"</body>" in body:
                body = body.replace(b"</body>", js + b"</body>", 1)
            else:
                body = body + js

        # fix Content-Length
        new_headers=[]
        for k,v in headers:
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(body))))

        start_response(meta.get("status","200 OK"), new_headers, meta.get("exc_info"))
        return [body]

try:
    if "application" in globals():
        _a = globals().get("application")
        if _a is not None and not getattr(_a, "__VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2__", False):
            _mw = VSPRunsExportZipBtnMWP0V2(_a)
            setattr(_mw, "__VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2__", True)
            globals()["application"] = _mw
except Exception:
    pass
# === /VSP_RUNS_EXPORT_ZIP_INJECT_MW_P0_V2 ===
'''

p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] appended MW injector V2")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
