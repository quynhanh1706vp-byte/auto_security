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
cp -f "$W" "${W}.bak_topfind_runid_mw_v4_${TS}"
echo "[BACKUP] ${W}.bak_topfind_runid_mw_v4_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import py_compile, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V4"
if marker in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

block = r'''
# --- VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V4 ---
# Commercial+ strict: /api/vsp/top_findings_v1 must include run_id == /api/vsp/rid_latest.rid
try:
    import json as _json
    import copy as _copy

    class _VspTopFindRunIdFixMwV4:
        def __init__(self, app):
            self.app = app

        def _call_inner_get_json(self, environ, path):
            # call inner app for GET path, capture body+headers
            env2 = _copy.deepcopy(environ)
            env2["REQUEST_METHOD"] = "GET"
            env2["PATH_INFO"] = path
            env2["QUERY_STRING"] = ""
            env2["CONTENT_LENGTH"] = "0"
            env2.pop("wsgi.input", None)

            cap = {"status": None, "headers": None, "exc": None}
            def sr(status, headers, exc_info=None):
                cap["status"]=status
                cap["headers"]=list(headers or [])
                cap["exc"]=exc_info
                return None

            it = self.app(env2, sr)
            body = b"".join(it)
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

            ctype = ""
            for k,v in cap["headers"] or []:
                if (k or "").lower() == "content-type":
                    ctype = v or ""
                    break

            if "application/json" not in (ctype or "").lower():
                return None
            try:
                return _json.loads(body.decode("utf-8","replace"))
            except Exception:
                return None

        def __call__(self, environ, start_response):
            path = environ.get("PATH_INFO","") or ""

            cap = {"status": None, "headers": None, "exc": None}
            def _sr(status, headers, exc_info=None):
                cap["status"]=status
                cap["headers"]=list(headers or [])
                cap["exc"]=exc_info
                return None

            it = self.app(environ, _sr)
            status = cap["status"] or "200 OK"
            headers = cap["headers"] or []
            exc = cap["exc"]

            # helper header ops
            def _get(name):
                n=name.lower()
                for k,v in headers:
                    if (k or "").lower()==n:
                        return v
                return ""

            def _set(name, val):
                n=name.lower()
                out=[]
                done=False
                for k,v in headers:
                    if (k or "").lower()==n:
                        if not done:
                            out.append((name,val)); done=True
                    else:
                        out.append((k,v))
                if not done:
                    out.append((name,val))
                return out

            def _drop(name):
                n=name.lower()
                return [(k,v) for (k,v) in headers if (k or "").lower()!=n]

            ctype = (_get("Content-Type") or "").lower()

            # only touch top_findings endpoint JSON
            if path != "/api/vsp/top_findings_v1" or "application/json" not in ctype:
                start_response(status, headers, exc)
                return it

            body = b"".join(it)
            try:
                close = getattr(it, "close", None)
                if callable(close): close()
            except Exception:
                pass

            try:
                j = _json.loads(body.decode("utf-8","replace"))
            except Exception:
                j = None

            if not isinstance(j, dict) or not j.get("ok", False):
                headers = _set("X-VSP-TOPFIND-RUNID-FIX", "skip")
                start_response(status, headers, exc)
                return [body]

            if j.get("run_id"):
                headers = _set("X-VSP-TOPFIND-RUNID-FIX", "already")
                start_response(status, headers, exc)
                return [body]

            # resolve rid_latest via inner call
            rid = None
            try:
                jl = self._call_inner_get_json(environ, "/api/vsp/rid_latest")
                if isinstance(jl, dict):
                    rid = jl.get("rid") or jl.get("run_id")
            except Exception:
                rid = None

            if rid:
                j["run_id"] = rid
                j.setdefault("marker", marker)
                new_body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                headers = _drop("Content-Length")
                headers = _set("Content-Length", str(len(new_body)))
                headers = _set("Content-Type", "application/json")
                headers = _set("X-VSP-TOPFIND-RUNID-FIX", "1")
                start_response(status, headers, exc)
                return [new_body]

            headers = _set("X-VSP-TOPFIND-RUNID-FIX", "no-rid")
            start_response(status, headers, exc)
            return [body]

    # wrap callable(s) served by gunicorn
    for _name in ("application", "app"):
        _obj = globals().get(_name)
        if _obj is not None:
            try:
                globals()[_name] = _VspTopFindRunIdFixMwV4(_obj)
            except Exception:
                pass
except Exception:
    pass
# --- end VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V4 ---
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended MW V4 top_findings run_id fixer")
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick check headers =="
curl -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'x-vsp-topfind-runid-fix|content-type' || true

echo "== quick check body =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"run_id=",j.get("run_id"),"marker=",j.get("marker"));'
