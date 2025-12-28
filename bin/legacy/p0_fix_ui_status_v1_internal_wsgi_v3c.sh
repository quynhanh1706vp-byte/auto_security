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

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_uistatus_v3c_${TS}"
echo "[BACKUP] ${W}.bak_uistatus_v3c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P0_UI_STATUS_V1 ====================="
end   = "# ===================== /VSP_P0_UI_STATUS_V1 ====================="
if start not in s or end not in s:
    print("[ERR] markers not found")
    raise SystemExit(2)

block = textwrap.dedent(r"""
# ===================== VSP_P0_UI_STATUS_V1 =====================
# Ops endpoint: quick health of 3 tabs + core API (NO dashboard dependency).
# Commercial rule: NEVER 500. Always return JSON 200.
# Implementation: INTERNAL WSGI subrequests (no loopback HTTP).
try:
    import json, time, traceback, io, sys

    def _json_resp(start_response, obj):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(b))),
        ])
        return [b]

    def _wsgi_call(inner, path, method="GET", query_string="", max_read=400000):
        qs = query_string or ""
        uri = path + (("?" + qs) if qs else "")
        env = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": qs,
            "SCRIPT_NAME": "",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "SERVER_NAME": "127.0.0.1",
            "SERVER_PORT": "8910",
            "REMOTE_ADDR": "127.0.0.1",
            "REQUEST_URI": uri,
            "RAW_URI": uri,
            "wsgi.version": (1, 0),
            "wsgi.url_scheme": "http",
            "wsgi.input": io.BytesIO(b""),
            "wsgi.errors": sys.stderr,
            "wsgi.multithread": True,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "HTTP_HOST": "127.0.0.1:8910",
            "HTTP_USER_AGENT": "VSP-UI-Status/1.3",
            "HTTP_ACCEPT": "*/*",
            "HTTP_ACCEPT_LANGUAGE": "en-US,en;q=0.9",
            "HTTP_CONNECTION": "close",
        }

        status_line = {"v": "500 INTERNAL"}
        headers = {"v": []}
        def _sr(st, hdrs, exc_info=None):
            status_line["v"] = st
            headers["v"] = hdrs or []
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
                if hasattr(it, "close"):
                    it.close()
            except Exception:
                pass
        except Exception as e:
            err = str(e)

        ms = int((time.time() - t0) * 1000)
        try:
            code = int((status_line["v"].split(" ", 1)[0] or "0").strip())
        except Exception:
            code = None

        hdr_map = {}
        try:
            for k, v in (headers["v"] or []):
                if k:
                    hdr_map[str(k).lower()] = str(v)
        except Exception:
            pass

        # Return full body for small JSON only (release_latest JSON is small)
        body_text = None
        ct = (hdr_map.get("content-type","") or "").lower()
        if method != "HEAD" and body and ("application/json" in ct) and len(body) <= 200000:
            body_text = body.decode("utf-8","replace")

        return {"method": method, "path": path, "qs": qs, "code": code, "ms": ms,
                "bytes": len(body), "err": err, "ct": hdr_map.get("content-type"), "body_text": body_text}

    def _wrap_ui_status(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/ui_status_v1":
                return inner(environ, start_response)
            try:
                checks = {}
                warn = []
                fails = []

                # REQUIRED: 3 tabs + runs api
                checks["tab:/runs"] = _wsgi_call(inner, "/runs", "GET", max_read=800000)
                checks["tab:/data_source"] = _wsgi_call(inner, "/data_source", "GET", max_read=200000)
                checks["tab:/settings"] = _wsgi_call(inner, "/settings", "GET", max_read=200000)
                checks["api:/api/vsp/runs?limit=1"] = _wsgi_call(inner, "/api/vsp/runs", "GET", "limit=1", max_read=120000)

                # OPTIONAL (WARN only): release_latest + download head
                checks["api:/api/vsp/release_latest"] = _wsgi_call(inner, "/api/vsp/release_latest", "GET", "", max_read=200000)
                rel = None
                try:
                    bt = checks["api:/api/vsp/release_latest"].get("body_text")
                    if bt and bt.lstrip().startswith("{"):
                        j = json.loads(bt)
                        if isinstance(j, dict):
                            rel = j.get("release_pkg") or None
                except Exception:
                    rel = None
                if rel:
                    checks["release:download_head"] = _wsgi_call(inner, "/api/vsp/release_pkg_download", "HEAD", "path=" + rel, max_read=1)

                def need200(k):
                    v = checks.get(k, {})
                    if v.get("code") != 200:
                        fails.append({"check": k, "reason": f"code={v.get('code')}", "err": v.get("err")})

                def need_bytes_ge(k, n):
                    v = checks.get(k, {})
                    if v.get("code") == 200 and int(v.get("bytes") or 0) < n:
                        fails.append({"check": k, "reason": f"bytes<{n}", "bytes": v.get("bytes")})

                # Required gates
                need200("tab:/runs");        need_bytes_ge("tab:/runs", 3000)
                need200("tab:/data_source"); need_bytes_ge("tab:/data_source", 500)
                need200("tab:/settings");    need_bytes_ge("tab:/settings", 500)
                need200("api:/api/vsp/runs?limit=1")

                # Optional warn
                if checks["api:/api/vsp/release_latest"].get("code") != 200:
                    warn.append({"check":"api:/api/vsp/release_latest","reason":f"code={checks['api:/api/vsp/release_latest'].get('code')}"})

                out = {
                    "ok": (len(fails) == 0),
                    "ts": int(time.time()),
                    "fails": fails,
                    "warn": warn,
                    "checks": {k: {kk: vv for kk, vv in v.items() if kk != "body_text"} for k, v in checks.items()},
                }
                return _json_resp(start_response, out)
            except Exception as e:
                return _json_resp(start_response, {"ok": False, "ts": int(time.time()), "err": str(e), "tb": traceback.format_exc(limit=8)})
        return _wsgi

    # apply wrapper last
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_ui_status(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_ui_status(app)

    print("[VSP_P0_UI_STATUS_V1] enabled v3c (internal wsgi + warn)")
except Exception as _e:
    print("[VSP_P0_UI_STATUS_V1] ERROR:", _e)
# ===================== /VSP_P0_UI_STATUS_V1 =====================
""").strip("\n")

pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2 = pat.sub(block, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] replaced ui_status block v3c")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: ui_status summary =="
curl -fsS "$BASE/api/vsp/ui_status_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"fails=",len(j.get("fails") or []),"warn=",len(j.get("warn") or []))
if j.get("warn"):
    print("warn0=", j["warn"][0])
PY
echo "[DONE]"
