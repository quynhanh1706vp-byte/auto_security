#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_force_ridlatest_v7_${TS}"
echo "[BACKUP] ${W}.bak_topfind_force_ridlatest_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7"
if MARK in s:
    print("[OK] already patched (marker exists)")
    raise SystemExit(0)

patch = r'''
# === {MARK} ===
# Commercial strict: if /api/vsp/top_findings_v1 is called WITHOUT rid=, internally re-call with rid_latest
try:
    import json as _json
    import io as _io
    import urllib.parse as _up
except Exception:
    _json=None
    _io=None
    _up=None

class __VspTopFindForceRidLatestMwV7:
    def __init__(self, app):
        self.app = app

    def _internal_get_json(self, path, query_string=""):
        if _io is None or _json is None:
            return 0, [], b"", None

        status_holder = {"status": "000", "headers": []}
        def _sr(status, headers, exc_info=None):
            status_holder["status"] = status
            status_holder["headers"] = list(headers or [])
            return None

        env = {
            "REQUEST_METHOD": "GET",
            "SCRIPT_NAME": "",
            "PATH_INFO": path,
            "QUERY_STRING": query_string or "",
            "SERVER_NAME": "localhost",
            "SERVER_PORT": "0",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "wsgi.version": (1, 0),
            "wsgi.url_scheme": "http",
            "wsgi.input": _io.BytesIO(b""),
            "wsgi.errors": _io.StringIO(),
            "wsgi.multithread": False,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "CONTENT_LENGTH": "0",
            "HTTP_X_VSP_INTERNAL_CALL": "1",  # recursion guard
        }

        chunks=[]
        try:
            it=self.app(env,_sr)
            for c in it:
                if c: chunks.append(c)
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass
        except Exception:
            return 0, [], b"", None

        body=b"".join(chunks)
        st=(status_holder["status"] or "000").split(" ",1)[0]
        try: code=int(st)
        except Exception: code=0

        ctype=""
        for k,v in status_holder["headers"]:
            if str(k).lower()=="content-type":
                ctype=str(v); break

        j=None
        if code==200 and "application/json" in ctype.lower():
            try: j=_json.loads(body.decode("utf-8", errors="replace"))
            except Exception: j=None
        return code, status_holder["headers"], body, j

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/top_findings_v1":
            return self.app(environ, start_response)

        # do not rewrite internal calls
        if environ.get("HTTP_X_VSP_INTERNAL_CALL") == "1":
            return self.app(environ, start_response)

        # parse query
        qs = environ.get("QUERY_STRING") or ""
        if _up is None:
            return self.app(environ, start_response)
        q = _up.parse_qs(qs, keep_blank_values=True)

        # If client already specifies rid=, pass through but normalize headers
        if "rid" in q and (q["rid"] and q["rid"][0]):
            captured={"status":None,"headers":None}
            def _sr(status, headers, exc_info=None):
                captured["status"]=status
                captured["headers"]=list(headers or [])
                return None
            chunks=[]
            it=self.app(environ,_sr)
            for c in it:
                if c: chunks.append(c)
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass
            status=captured["status"] or "500 INTERNAL SERVER ERROR"
            headers=captured["headers"] or []
            body=b"".join(chunks)
            # remove duplicate proof headers, set single marker
            headers=[(k,v) for (k,v) in headers if str(k).lower()!="x-vsp-topfind-runid-fix"]
            headers.append(("X-VSP-TOPFIND-RUNID-FIX", "passthrough"))
            start_response(status, headers)
            return [body]

        # Otherwise: force rid_latest
        rc, rh, rb, rj = self._internal_get_json("/api/vsp/rid_latest","")
        rid = None
        if isinstance(rj, dict) and rj.get("ok") in (True,"true",1):
            rid = rj.get("rid")

        if not rid:
            # fail open
            headers=[("Content-Type","application/json; charset=utf-8"), ("X-VSP-TOPFIND-RUNID-FIX","no-ridlatest")]
            start_response("200 OK", headers)
            return [rb if rb else b'{"ok":false,"marker":"{MARK}","error":"no rid_latest"}']

        # rebuild qs: keep limit if present
        limit = (q.get("limit") or [""])[0]
        new_qs = "rid=" + _up.quote(str(rid))
        if limit:
            new_qs += "&limit=" + _up.quote(str(limit))

        # internal call to same endpoint WITH rid
        code, h2, b2, j2 = self._internal_get_json("/api/vsp/top_findings_v1", new_qs)

        # respond with internal result; normalize proof header to single
        status_line = "200 OK" if code==200 else (str(code) + " ERROR")
        headers = [(k,v) for (k,v) in (h2 or []) if str(k).lower()!="x-vsp-topfind-runid-fix"]
        headers.append(("X-VSP-TOPFIND-RUNID-FIX", "ok-v7"))
        start_response(status_line, headers)
        return [b2]

# install outermost
try:
    _base = globals().get("application") or globals().get("app")
    if _base is not None and _base.__class__.__name__ != "__VspTopFindForceRidLatestMwV7":
        globals()["application"] = __VspTopFindForceRidLatestMwV7(_base)
except Exception:
    pass
# === /{MARK} ===
'''.replace("{MARK}", MARK)

p.write_text(s + "\n" + patch, encoding="utf-8")
print("[OK] appended", MARK)
PY

python3 -m py_compile "$W" >/dev/null
echo "[OK] py_compile OK"

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

echo "== proof (no rid param) =="
curl -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'http/|content-type|x-vsp-topfind-runid-fix' || true
curl -sS "$BASE/api/vsp/top_findings_v1?limit=1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"),"marker=",j.get("marker"),"total=",j.get("total"))
PY

echo "== proof (explicit rid_latest) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"),"total=",j.get("total"))
PY

echo "[OK] done"
