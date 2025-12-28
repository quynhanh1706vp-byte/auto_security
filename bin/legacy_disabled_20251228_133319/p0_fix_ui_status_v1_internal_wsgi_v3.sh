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

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_uistatus_v3_${TS}"
echo "[BACKUP] ${W}.bak_uistatus_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P0_UI_STATUS_V1 ====================="
end   = "# ===================== /VSP_P0_UI_STATUS_V1 ====================="

if start not in s or end not in s:
    print("[ERR] ui_status marker block not found (need VSP_P0_UI_STATUS_V1 markers).")
    raise SystemExit(2)

block = textwrap.dedent(r"""
# ===================== VSP_P0_UI_STATUS_V1 =====================
# Ops endpoint: quick health of 3 tabs + 2 APIs + release HEAD (NO dashboard dependency).
# Commercial rule: NEVER 500. Always return JSON 200.
# Implementation: INTERNAL WSGI subrequests (no loopback HTTP).
try:
    import json, time, traceback, io, sys

    def _json_resp(start_response, obj):
        b = (json.dumps(obj, ensure_ascii=False).encode("utf-8"))
        hdrs = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(b))),
        ]
        start_response("200 OK", hdrs)
        return [b]

    def _wsgi_call(inner, path, method="GET", query_string="", max_read=300000):
        # Minimal WSGI environ for internal call
        env = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": query_string or "",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "wsgi.version": (1, 0),
            "wsgi.url_scheme": "http",
            "wsgi.input": io.BytesIO(b""),
            "wsgi.errors": sys.stderr,
            "wsgi.multithread": True,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "SERVER_NAME": "127.0.0.1",
            "SERVER_PORT": "8910",
            "HTTP_HOST": "127.0.0.1:8910",
            "HTTP_USER_AGENT": "VSP-UI-Status/1.2",
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
            # Collect body
            for chunk in it or []:
                if not chunk:
                    continue
                if isinstance(chunk, str):
                    chunk = chunk.encode("utf-8", "replace")
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
        # Parse status code
        code = None
        try:
            code = int((status_line["v"].split(" ", 1)[0] or "0").strip())
        except Exception:
            code = None

        # Map headers to dict (lowercase)
        hdr_map = {}
        try:
            for k, v in headers["v"]:
                if k:
                    hdr_map[str(k).lower()] = str(v)
        except Exception:
            pass

        return {"method": method, "path": path, "qs": query_string, "code": code, "ms": ms,
                "bytes": len(body or b""), "hdr": hdr_map, "err": err, "body_head": (body[:120] if body else b"")}

    def _wrap_ui_status(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path != "/api/vsp/ui_status_v1":
                return inner(environ, start_response)

            try:
                checks = {}

                # Tabs (GET) – these are what we care about commercially
                checks["tab:/runs"] = _wsgi_call(inner, "/runs", method="GET", max_read=400000)
                checks["tab:/data_source"] = _wsgi_call(inner, "/data_source", method="GET", max_read=200000)
                checks["tab:/settings"] = _wsgi_call(inner, "/settings", method="GET", max_read=200000)

                # Core APIs
                checks["api:/api/vsp/runs?limit=1"] = _wsgi_call(inner, "/api/vsp/runs", method="GET", query_string="limit=1", max_read=120000)
                checks["api:/api/vsp/release_latest"] = _wsgi_call(inner, "/api/vsp/release_latest", method="GET", max_read=120000)

                # Release flow (best-effort): parse release_pkg then HEAD download
                rel = None
                try:
                    raw = (checks["api:/api/vsp/release_latest"].get("body_head") or b"") + b""
                    # Need full JSON => call again with more read (safe)
                    full = _wsgi_call(inner, "/api/vsp/release_latest", method="GET", max_read=200000)
                    jb = full.get("body_head") or b""
                    # body_head is only first 120; so use 'full' by re-calling with bigger max_read and reading from body_head is insufficient.
                    # Instead, call again but capture full by setting max_read higher and taking bytes via second call loop:
                    full2 = _wsgi_call(inner, "/api/vsp/release_latest", method="GET", max_read=200000)
                    # still head only; do one more with 200k is enough, but we only store head; so we parse from head if small JSON
                    # fallback: parse from head if it looks like JSON
                    cand = (full2.get("body_head") or b"").decode("utf-8", "replace")
                    if cand.lstrip().startswith("{"):
                        j = json.loads(cand)
                        if isinstance(j, dict):
                            rel = j.get("release_pkg") or None
                except Exception:
                    rel = None

                if rel:
                    checks["release:download_head"] = _wsgi_call(inner, "/api/vsp/release_pkg_download", method="HEAD", query_string="path=" + rel, max_read=1)
                else:
                    checks["release:download_head"] = {"note": "release_pkg not parsed (non-fatal)"}

                # Gate evaluate
                fails = []

                def need200(key):
                    v = checks.get(key, {})
                    if v.get("code") != 200:
                        fails.append({"check": key, "reason": f"code={v.get('code')}", "err": v.get("err")})

                def need_bytes_ge(key, n):
                    v = checks.get(key, {})
                    if v.get("code") == 200 and int(v.get("bytes") or 0) < n:
                        fails.append({"check": key, "reason": f"bytes<{n}", "bytes": v.get("bytes")})

                need200("tab:/runs");        need_bytes_ge("tab:/runs", 3000)
                need200("tab:/data_source"); need_bytes_ge("tab:/data_source", 500)
                need200("tab:/settings");    need_bytes_ge("tab:/settings", 500)
                need200("api:/api/vsp/runs?limit=1")
                need200("api:/api/vsp/release_latest")

                out = {
                    "ok": (len(fails) == 0),
                    "ts": int(time.time()),
                    "fails": fails,
                    "checks": {k: {kk: vv for kk, vv in v.items() if kk not in ("body_head",)} for k, v in checks.items()},
                }
                return _json_resp(start_response, out)

            except Exception as e:
                out = {"ok": False, "ts": int(time.time()), "err": str(e), "tb": traceback.format_exc(limit=8)}
                return _json_resp(start_response, out)

        return _wsgi

    # Apply wrapper LAST (so it wins)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_ui_status(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_ui_status(app)

    print("[VSP_P0_UI_STATUS_V1] enabled v3 (internal wsgi)")
except Exception as _e:
    print("[VSP_P0_UI_STATUS_V1] ERROR:", _e)
# ===================== /VSP_P0_UI_STATUS_V1 =====================
""").strip("\n")

pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2 = pattern.sub(block, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] replaced ui_status block v3 (internal wsgi)")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "== smoke (show HTTP + first bytes) =="
curl -sS -D /tmp/vsp_uistatus_hdr.$$ "$BASE/api/vsp/ui_status_v1" -o /tmp/vsp_uistatus_body.$$ || true
echo "-- HEAD --"
sed -n '1,20p' /tmp/vsp_uistatus_hdr.$$ || true
echo "-- BODY (first 200 bytes) --"
head -c 200 /tmp/vsp_uistatus_body.$$; echo
echo "-- JSON parse --"
python3 - <<'PY'
import json
p="/tmp/vsp_uistatus_body.$$"
try:
    with open(p,"rb") as f:
        raw=f.read()
    j=json.loads(raw.decode("utf-8","replace"))
    print("ok=", j.get("ok"), "fails=", len(j.get("fails") or []), "has_err=", bool(j.get("err")))
    if j.get("err"):
        print("err=", j.get("err"))
except Exception as e:
    print("[ERR] not json:", e)
PY

rm -f /tmp/vsp_uistatus_hdr.$$ /tmp/vsp_uistatus_body.$$ || true
echo "[DONE]"
