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
cp -f "$W" "${W}.bak_topfind_runid_mw_v5_${TS}"
echo "[BACKUP] ${W}.bak_topfind_runid_mw_v5_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import py_compile, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V5"
if marker in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

block = r'''
# --- VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V5 ---
# Fix top_findings.run_id via WSGI-level internal call to /api/vsp/rid_latest with proper environ.
try:
    import json as _json
    import io as _io

    class _VspTopFindRunIdFixMwV5:
        def __init__(self, app):
            self.app = app

        def _inner_get_json(self, environ, path):
            # Build minimal valid WSGI environ (do NOT deepcopy whole environ)
            scheme = environ.get("wsgi.url_scheme", "http")
            host = environ.get("HTTP_HOST") or environ.get("SERVER_NAME") or "127.0.0.1"
            server_name = environ.get("SERVER_NAME") or host.split(":")[0]
            server_port = environ.get("SERVER_PORT") or (host.split(":")[1] if ":" in host else ("443" if scheme=="https" else "80"))
            proto = environ.get("SERVER_PROTOCOL") or "HTTP/1.1"

            env2 = {
                "REQUEST_METHOD": "GET",
                "SCRIPT_NAME": "",
                "PATH_INFO": path,
                "QUERY_STRING": "",
                "SERVER_NAME": server_name,
                "SERVER_PORT": str(server_port),
                "SERVER_PROTOCOL": proto,
                "wsgi.version": (1, 0),
                "wsgi.url_scheme": scheme,
                "wsgi.input": _io.BytesIO(b""),
                "wsgi.errors": environ.get("wsgi.errors") or _io.StringIO(),
                "wsgi.multithread": False,
                "wsgi.multiprocess": True,
                "wsgi.run_once": False,
                "HTTP_HOST": host,
                "REMOTE_ADDR": environ.get("REMOTE_ADDR","127.0.0.1"),
                "HTTP_USER_AGENT": "VSP-MW-V5",
            }

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

            # try parse json regardless of content-type
            try:
                j = _json.loads(body.decode("utf-8","replace"))
            except Exception:
                j = None

            ctype = ""
            for k,v in (cap["headers"] or []):
                if (k or "").lower()=="content-type":
                    ctype = v or ""
                    break
            return j, (cap["status"] or ""), ctype

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

            # always mark we ran
            headers = _set("X-VSP-TOPFIND-RUNID-FIX-V5", "hit")

            if not isinstance(j, dict) or not j.get("ok", False):
                start_response(status, headers, exc)
                return [body]

            if j.get("run_id"):
                headers = _set("X-VSP-TOPFIND-RUNID-FIX", "already")
                start_response(status, headers, exc)
                return [body]

            jl, st, ct = self._inner_get_json(environ, "/api/vsp/rid_latest")
            rid = None
            if isinstance(jl, dict):
                rid = jl.get("rid") or jl.get("run_id")

            headers = _set("X-VSP-RIDCALL-STATUS", st[:32])
            headers = _set("X-VSP-RIDCALL-CTYPE", (ct or "")[:64])

            if rid:
                j["run_id"] = rid
                j.setdefault("marker", marker)
                new_body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                headers = _drop("Content-Length")
                headers = _set("Content-Length", str(len(new_body)))
                headers = _set("Content-Type", "application/json; charset=utf-8")
                headers = _set("X-VSP-TOPFIND-RUNID-FIX", "1")
                start_response(status, headers, exc)
                return [new_body]

            headers = _set("X-VSP-TOPFIND-RUNID-FIX", "no-rid")
            start_response(status, headers, exc)
            return [body]

    for _name in ("application", "app"):
        _obj = globals().get(_name)
        if _obj is not None:
            try:
                globals()[_name] = _VspTopFindRunIdFixMwV5(_obj)
            except Exception:
                pass
except Exception:
    pass
# --- end VSP_P2_WSGI_MW_TOPFIND_RUNID_FIX_V5 ---
'''
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended MW V5 top_findings run_id fixer")
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== header proof =="
curl -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'x-vsp-topfind-runid-fix|x-vsp-ridcall-|content-type' || true

echo "== body proof =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"run_id=",j.get("run_id"),"marker=",j.get("marker"));'
