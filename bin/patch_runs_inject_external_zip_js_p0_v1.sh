#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_extzip_${TS}"
echo "[BACKUP] ${F}.bak_runs_extzip_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_INJECT_EXTZIP_JS_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

inj = r'''
# === VSP_RUNS_INJECT_EXTZIP_JS_P0_V1 ===
class VSPRunsInjectExtZipJSMWP0V1:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        if (environ.get("PATH_INFO") or "") != "/runs":
            return self.app(environ, start_response)

        meta={}
        def sr(status, headers, exc_info=None):
            meta["status"]=status; meta["headers"]=headers; meta["exc_info"]=exc_info
            return lambda _x: None

        it = self.app(environ, sr)
        body=b""
        try:
            for c in it:
                if c: body += c
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass

        headers = meta.get("headers") or []
        ct=""
        for k,v in headers:
            if str(k).lower()=="content-type":
                ct=str(v); break

        if ("text/html" in ct) and (MARK.encode() not in body):
            ts = str(int(time.time()))
            tag = (f'\n<!-- {MARK} -->\n'
                   f'<script src="/static/js/vsp_runs_export_zip_patch_p0_v4.js?ts={ts}"></script>\n').encode("utf-8","replace")
            if b"</body>" in body:
                body = body.replace(b"</body>", tag + b"</body>", 1)
            else:
                body = body + tag

        newh=[]
        for k,v in headers:
            if str(k).lower()=="content-length": continue
            newh.append((k,v))
        newh.append(("Content-Length", str(len(body))))
        start_response(meta.get("status","200 OK"), newh, meta.get("exc_info"))
        return [body]

try:
    if "application" in globals():
        _a = globals().get("application")
        if _a is not None and not getattr(_a, "__VSP_RUNS_INJECT_EXTZIP_JS_P0_V1__", False):
            _mw = VSPRunsInjectExtZipJSMWP0V1(_a)
            setattr(_mw, "__VSP_RUNS_INJECT_EXTZIP_JS_P0_V1__", True)
            globals()["application"] = _mw
except Exception:
    pass
# === /VSP_RUNS_INJECT_EXTZIP_JS_P0_V1 ===
'''
p.write_text(s.rstrip()+"\n\n"+inj+"\n", encoding="utf-8")
print("[OK] appended MW:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
