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
cp -f "$W" "${W}.bak_uistatusfix_${TS}"
echo "[BACKUP] ${W}.bak_uistatusfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P0_UI_STATUS_V1 ====================="
end   = "# ===================== /VSP_P0_UI_STATUS_V1 ====================="

if start not in s or end not in s:
    print("[ERR] ui_status marker block not found. Did you run p0_add_ui_status_v1.sh?")
    raise SystemExit(2)

block = textwrap.dedent(r"""
# ===================== VSP_P0_UI_STATUS_V1 =====================
# Ops endpoint: quick health of 3 tabs + 2 APIs + release download flow (NO dashboard dependency).
# Commercial rule: NEVER 500. Always return JSON {ok:..., err/tb if any}.
try:
    import json, time, traceback
    from urllib import request

    def _json_resp(start_response, code, obj):
        b = (json.dumps(obj, ensure_ascii=False).encode("utf-8"))
        hdrs = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(b))),
        ]
        start_response(code, hdrs)
        return [b]

    def _http_probe(url, method="GET", timeout=0.6, max_read=200000):
        t0 = time.time()
        code = None
        hdrs = {}
        nbytes = 0
        err = None
        try:
            req = request.Request(url, method=method, headers={
                "User-Agent": "VSP-UI-Status/1.1",
                "Connection": "close",
            })
            with request.urlopen(req, timeout=timeout) as r:
                code = getattr(r, "status", None)
                hdrs = {k.lower(): v for k, v in (r.headers.items() if r.headers else [])}
                if method != "HEAD":
                    data = r.read(max_read)
                    nbytes = len(data) if data else 0
        except Exception as e:
            err = str(e)
        ms = int((time.time() - t0) * 1000)
        return {"url": url, "method": method, "code": code, "ms": ms, "bytes": nbytes, "err": err}

    def _wrap_ui_status(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path != "/api/vsp/ui_status_v1":
                return inner(environ, start_response)

            # Always return JSON 200 even on internal error
            try:
                base = "http://127.0.0.1:8910"

                checks = {}

                # Tabs GET (minimum viable checks)
                checks["tab:/runs:get"]        = _http_probe(base + "/runs", method="GET", timeout=0.8)
                checks["tab:/data_source:get"] = _http_probe(base + "/data_source", method="GET", timeout=0.8)
                checks["tab:/settings:get"]    = _http_probe(base + "/settings", method="GET", timeout=0.8)

                # Core APIs
                checks["api:/api/vsp/runs?limit=1"]      = _http_probe(base + "/api/vsp/runs?limit=1", method="GET", timeout=0.8)
                checks["api:/api/vsp/release_latest"]    = _http_probe(base + "/api/vsp/release_latest", method="GET", timeout=0.8)

                # Release flow (best-effort): parse release_pkg then HEAD download
                rel = None
                try:
                    req = request.Request(base + "/api/vsp/release_latest", headers={"User-Agent":"VSP-UI-Status/1.1","Connection":"close"})
                    with request.urlopen(req, timeout=0.8) as r:
                        raw = r.read(200000)
                    j = json.loads(raw.decode("utf-8", "replace"))
                    if isinstance(j, dict):
                        rel = j.get("release_pkg") or None
                except Exception:
                    rel = None

                if rel:
                    checks["release:download_head"] = _http_probe(base + "/api/vsp/release_pkg_download?path=" + rel, method="HEAD", timeout=0.8)
                else:
                    checks["release:download_head"] = {"note":"release_pkg empty or not parseable"}

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

                need200("tab:/runs:get");        need_bytes_ge("tab:/runs:get", 3000)
                need200("tab:/data_source:get"); need_bytes_ge("tab:/data_source:get", 500)
                need200("tab:/settings:get");    need_bytes_ge("tab:/settings:get", 500)
                need200("api:/api/vsp/runs?limit=1")
                need200("api:/api/vsp/release_latest")

                ok = (len(fails) == 0)

                out = {"ok": ok, "ts": int(time.time()), "fails": fails, "checks": checks}
                return _json_resp(start_response, "200 OK", out)

            except Exception as e:
                tb = traceback.format_exc(limit=6)
                out = {"ok": False, "ts": int(time.time()), "err": str(e), "tb": tb}
                return _json_resp(start_response, "200 OK", out)

        return _wsgi

    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_ui_status(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_ui_status(application)

    print("[VSP_P0_UI_STATUS_V1] enabled v2 (no-500)")
except Exception as _e:
    print("[VSP_P0_UI_STATUS_V1] ERROR:", _e)
# ===================== /VSP_P0_UI_STATUS_V1 =====================
""").strip("\n")

# replace whole block
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2 = pattern.sub(block, s, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] replaced ui_status block v2")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "== smoke: /api/vsp/ui_status_v1 (must be JSON, never 500) =="
curl -sS "$BASE/api/vsp/ui_status_v1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "has_err=", bool(j.get("err")), "fails=", len(j.get("fails") or []))
if j.get("err"):
    print("err=", j.get("err"))
    print("tb=", (j.get("tb") or "").splitlines()[:3])
PY

echo "[DONE]"
