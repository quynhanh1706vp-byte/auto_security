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
cp -f "$W" "${W}.bak_topfind_runid_mw_v6_${TS}"
echo "[BACKUP] ${W}.bak_topfind_runid_mw_v6_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TOPFIND_RUNID_WSGI_MW_V6"
if MARK in s:
    print("[OK] already patched (marker exists)")
    raise SystemExit(0)

patch = r'''
# === {MARK} ===
# Commercial+ strict: ensure /api/vsp/top_findings_v1 returns run_id == rid_latest (no HTTP; internal WSGI call)
try:
    import json as _json
    import io as _io
except Exception:
    _json=None
    _io=None

class __VspTopFindRunIdFixMwV6:
    def __init__(self, app):
        self.app = app

    def _internal_get_json(self, path, query_string=""):
        """
        Internal WSGI call to the same stack, guarded to avoid recursion.
        Returns (status_code:int, headers:list[(k,v)], body_bytes:bytes, parsed_json:dict|None)
        """
        if _io is None or _json is None:
            return 0, [], b"", None

        status_holder = {"status": "000", "headers": []}

        def _sr(status, headers, exc_info=None):
            status_holder["status"] = status
            status_holder["headers"] = headers or []
            return None

        # Minimal environ
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
            "HTTP_X_VSP_INTERNAL_CALL": "1",  # guard
        }

        body_chunks = []
        try:
            it = self.app(env, _sr)
            for chunk in it:
                if chunk:
                    body_chunks.append(chunk)
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass
        except Exception:
            return 0, [], b"", None

        body = b"".join(body_chunks)
        st = status_holder["status"].split(" ", 1)[0]
        try:
            code = int(st)
        except Exception:
            code = 0

        # parse JSON if looks like json
        ctype = ""
        for (k, v) in status_holder["headers"]:
            if str(k).lower() == "content-type":
                ctype = str(v)
                break
        j = None
        if code == 200 and "application/json" in ctype.lower():
            try:
                j = _json.loads(body.decode("utf-8", errors="replace"))
            except Exception:
                j = None
        return code, status_holder["headers"], body, j

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO") or ""
            if path != "/api/vsp/top_findings_v1":
                return self.app(environ, start_response)

            # guard: do not rewrite internal calls
            if environ.get("HTTP_X_VSP_INTERNAL_CALL") == "1":
                return self.app(environ, start_response)

            # capture downstream response
            captured = {"status": None, "headers": None}
            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers or [])
                return None

            chunks = []
            it = self.app(environ, _sr)
            for c in it:
                if c:
                    chunks.append(c)
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

            status = captured["status"] or "500 INTERNAL SERVER ERROR"
            headers = captured["headers"] or []
            body = b"".join(chunks)

            # only touch JSON 200
            code_s = status.split(" ",1)[0]
            if code_s != "200":
                start_response(status, headers)
                return [body]

            ctype = ""
            for (k,v) in headers:
                if str(k).lower()=="content-type":
                    ctype=str(v); break
            if "application/json" not in ctype.lower():
                start_response(status, headers)
                return [body]

            # parse json
            try:
                j = _json.loads(body.decode("utf-8", errors="replace"))
            except Exception:
                j = None
            if not isinstance(j, dict):
                start_response(status, headers)
                return [body]

            # only if ok=true and run_id missing/None/empty
            okv = j.get("ok")
            if okv not in (True, "true", 1):
                start_response(status, headers)
                return [body]

            run_id = j.get("run_id")
            if run_id not in (None, "", "null"):
                # still add proof header
                headers.append(("X-VSP-TOPFIND-RUNID-FIX", "already"))
                start_response(status, headers)
                return [body]

            # internal call rid_latest
            rc, rh, rb, rj = self._internal_get_json("/api/vsp/rid_latest", "")
            rid = None
            if isinstance(rj, dict) and rj.get("ok") in (True,"true",1):
                rid = rj.get("rid")

            if rid:
                j["run_id"] = rid
                # marker for audit
                j.setdefault("marker", "{MARK}")
                out = _json.dumps(j, ensure_ascii=False, separators=(",",":")).encode("utf-8")
                # replace content-length
                headers = [(k,v) for (k,v) in headers if str(k).lower()!="content-length"]
                headers.append(("Content-Length", str(len(out))))
                headers.append(("X-VSP-TOPFIND-RUNID-FIX", "ok"))
                start_response(status, headers)
                return [out]
            else:
                headers.append(("X-VSP-TOPFIND-RUNID-FIX", "no-rid"))
                start_response(status, headers)
                return [body]

        except Exception:
            # fail open
            return self.app(environ, start_response)

# install outermost (idempotent)
try:
    _base = globals().get("application") or globals().get("app")
    if _base is not None and _base.__class__.__name__ != "__VspTopFindRunIdFixMwV6":
        globals()["application"] = __VspTopFindRunIdFixMwV6(_base)
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

echo "== quick proof =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"

curl -fsSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'content-type|x-vsp-topfind-runid-fix' || true

curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" \
| python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "run_id=", j.get("run_id"), "marker=", j.get("marker"), "total=", j.get("total"))
PY

echo "[OK] done"
