#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_UI_STATUS_HARDHOOK_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_hardhook_${TS}"
echo "[BACKUP] ${W}.bak_hardhook_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_UI_STATUS_HARDHOOK_V1" in s:
    print("[SKIP] hardhook already present")
    raise SystemExit(0)

hook = textwrap.dedent(r"""
# ===================== VSP_P0_UI_STATUS_HARDHOOK_V1 =====================
# Must be placed at END of module to avoid later rebind overriding middleware.
try:
    import json, time, io, sys, traceback

    def _uistatus_json(start_response, obj):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(b))),
        ])
        return [b]

    def _uistatus_call(inner, path, method="GET", qs="", max_read=600000):
        uri = path + (("?" + qs) if qs else "")
        env = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": qs or "",
            "SCRIPT_NAME": "",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "SERVER_NAME": "127.0.0.1",
            "SERVER_PORT": "8910",
            "REMOTE_ADDR": "127.0.0.1",
            "REQUEST_URI": uri,
            "RAW_URI": uri,
            "wsgi.version": (1,0),
            "wsgi.url_scheme": "http",
            "wsgi.input": io.BytesIO(b""),
            "wsgi.errors": sys.stderr,
            "wsgi.multithread": True,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "HTTP_HOST": "127.0.0.1:8910",
            "HTTP_USER_AGENT": "VSP-UI-Status/HardHook",
            "HTTP_ACCEPT": "*/*",
            "HTTP_CONNECTION": "close",
        }

        st = {"v":"500 INTERNAL"}
        hdrs = {"v":[]}
        def _sr(status, headers, exc_info=None):
            st["v"] = status
            hdrs["v"] = headers or []
            return None

        t0 = time.time()
        body = b""
        err = None
        try:
            it = inner(env, _sr)
            for chunk in it or []:
                if not chunk:
                    continue
                if isinstance(chunk, str):
                    chunk = chunk.encode("utf-8","replace")
                body += chunk
                if len(body) >= max_read:
                    break
            try:
                if hasattr(it, "close"): it.close()
            except Exception:
                pass
        except Exception as e:
            err = str(e)

        ms = int((time.time()-t0)*1000)
        try:
            code = int((st["v"].split(" ",1)[0] or "0").strip())
        except Exception:
            code = None
        return {"code": code, "ms": ms, "bytes": len(body), "err": err}

    def _uistatus_wrap(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/ui_status_v1":
                return inner(environ, start_response)
            try:
                checks = {}
                fails = []

                checks["tab:/runs"]        = _uistatus_call(inner, "/runs", "GET")
                checks["tab:/data_source"] = _uistatus_call(inner, "/data_source", "GET", max_read=250000)
                checks["tab:/settings"]    = _uistatus_call(inner, "/settings", "GET", max_read=250000)
                checks["api:/api/vsp/runs?limit=1"] = _uistatus_call(inner, "/api/vsp/runs", "GET", qs="limit=1", max_read=160000)

                def need200(k):
                    v = checks.get(k, {})
                    if v.get("code") != 200:
                        fails.append({"check": k, "reason": f"code={v.get('code')}", "err": v.get("err")})

                def need_bytes_ge(k, n):
                    v = checks.get(k, {})
                    if v.get("code") == 200 and int(v.get("bytes") or 0) < n:
                        fails.append({"check": k, "reason": f"bytes<{n}", "bytes": v.get("bytes")})

                need200("tab:/runs");        need_bytes_ge("tab:/runs", 3000)
                need200("tab:/data_source"); need_bytes_ge("tab:/data_source", 500)
                need200("tab:/settings");    need_bytes_ge("tab:/settings", 500)
                need200("api:/api/vsp/runs?limit=1")

                out = {"ok": (len(fails)==0), "ts": int(time.time()), "fails": fails, "checks": checks}
                return _uistatus_json(start_response, out)
            except Exception as e:
                out = {"ok": False, "ts": int(time.time()), "err": str(e), "tb": traceback.format_exc(limit=6)}
                return _uistatus_json(start_response, out)
        return _wsgi

    # Force wrap the final callable at end-of-file (wins against rebinding).
    if "application" in globals() and callable(globals().get("application")):
        application = _uistatus_wrap(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _uistatus_wrap(app)

    print("[VSP_P0_UI_STATUS_HARDHOOK_V1] installed")
except Exception as _e:
    print("[VSP_P0_UI_STATUS_HARDHOOK_V1] ERROR:", _e)
# ===================== /VSP_P0_UI_STATUS_HARDHOOK_V1 =====================
""").strip("\n")

p.write_text(s + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended hardhook at EOF")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "== smoke: ui_status (must be JSON) =="
curl -sS "$BASE/api/vsp/ui_status_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "fails=", len(j.get("fails") or []))
if j.get("fails"):
    print("fail0=", j["fails"][0])
PY
echo "[DONE]"
