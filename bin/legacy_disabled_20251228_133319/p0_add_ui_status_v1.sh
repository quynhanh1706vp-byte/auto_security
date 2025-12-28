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
MARK="VSP_P0_UI_STATUS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_uistatus_${TS}"
echo "[BACKUP] ${W}.bak_uistatus_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_UI_STATUS_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

anchor = "# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
idx = s.find(anchor)
if idx < 0:
    idx = len(s)

patch = textwrap.dedent(r"""
# ===================== VSP_P0_UI_STATUS_V1 =====================
# Ops endpoint: quick health of 3 tabs + 2 APIs + release download flow (no dashboard dependency).
try:
    import json, time
    from urllib import request, error

    def _json_resp(start_response, code, obj):
        b = (json.dumps(obj, ensure_ascii=False).encode("utf-8"))
        hdrs = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(b))),
        ]
        start_response(code, hdrs)
        return [b]

    def _http_probe(url, method="GET", timeout=0.8, max_read=200000):
        t0 = time.time()
        req = request.Request(url, method=method, headers={
            "User-Agent": "VSP-UI-Status/1.0",
            "Connection": "close",
        })
        code = None
        hdrs = {}
        nbytes = 0
        err = None
        try:
            with request.urlopen(req, timeout=timeout) as r:
                code = getattr(r, "status", None)
                hdrs = {k.lower(): v for k, v in (r.headers.items() if r.headers else [])}
                if method != "HEAD":
                    data = r.read(max_read)
                    nbytes = len(data) if data else 0
        except Exception as e:
            err = str(e)
        ms = int((time.time() - t0) * 1000)
        return {"url": url, "method": method, "code": code, "ms": ms, "bytes": nbytes, "headers": hdrs, "err": err}

    def _wrap_ui_status(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path == "/api/vsp/ui_status_v1":
                base = "http://127.0.0.1:8910"

                checks = {}
                # Tabs (HTML)
                for tab in ("/runs", "/data_source", "/settings"):
                    checks[f"tab:{tab}:head"] = _http_probe(base + tab, method="HEAD")
                    checks[f"tab:{tab}:get"]  = _http_probe(base + tab, method="GET")

                # Core APIs
                checks["api:/api/vsp/runs?limit=1"] = _http_probe(base + "/api/vsp/runs?limit=1", method="GET")
                checks["api:/api/vsp/release_latest"] = _http_probe(base + "/api/vsp/release_latest", method="GET")

                # Release flow (best-effort): parse release_pkg then HEAD download
                rel = None
                try:
                    j = None
                    a = checks["api:/api/vsp/release_latest"]
                    if a.get("code") == 200 and a.get("bytes", 0) > 0:
                        # We only read up to max_read; should be enough for JSON
                        # re-fetch smaller to parse accurately
                        b = _http_probe(base + "/api/vsp/release_latest", method="GET", max_read=200000)
                        if b.get("code") == 200 and b.get("bytes", 0) > 0 and not b.get("err"):
                            # parse from second probe by reading again (cheap)
                            req = request.Request(base + "/api/vsp/release_latest", headers={"User-Agent":"VSP-UI-Status/1.0","Connection":"close"})
                            with request.urlopen(req, timeout=0.8) as r:
                                raw = r.read(200000)
                            j = json.loads(raw.decode("utf-8", "replace"))
                    if isinstance(j, dict):
                        rel = j.get("release_pkg") or None
                except Exception:
                    rel = None

                if rel:
                    # Important: keep it HEAD to avoid downloading big tgz inside status endpoint
                    checks["release:download_head"] = _http_probe(base + "/api/vsp/release_pkg_download?path=" + rel, method="HEAD")
                else:
                    checks["release:download_head"] = {"ok": False, "note": "release_pkg empty or not parseable"}

                # Evaluate
                fails = []
                def _need200(k):
                    v = checks.get(k, {})
                    if v.get("code") != 200:
                        fails.append({"check": k, "reason": f"code={v.get('code')}", "err": v.get("err")})
                def _need_bytes_ge(k, n):
                    v = checks.get(k, {})
                    if v.get("code") == 200 and int(v.get("bytes") or 0) < n:
                        fails.append({"check": k, "reason": f"bytes<{n}", "bytes": v.get("bytes")})

                # Gate: 3 tabs GET bytes + 2 APIs 200
                _need200("tab:/runs:get");        _need_bytes_ge("tab:/runs:get", 3000)
                _need200("tab:/data_source:get"); _need_bytes_ge("tab:/data_source:get", 500)
                _need200("tab:/settings:get");    _need_bytes_ge("tab:/settings:get", 500)
                _need200("api:/api/vsp/runs?limit=1")
                _need200("api:/api/vsp/release_latest")

                ok = (len(fails) == 0)

                out = {
                    "ok": ok,
                    "ts": int(time.time()),
                    "fails": fails,
                    "checks": checks,
                }
                return _json_resp(start_response, "200 OK", out)

            return inner(environ, start_response)
        return _wsgi

    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_ui_status(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_ui_status(application)

    print("[VSP_P0_UI_STATUS_V1] enabled")
except Exception as _e:
    print("[VSP_P0_UI_STATUS_V1] ERROR:", _e)
# ===================== /VSP_P0_UI_STATUS_V1 =====================
""")

p.write_text(s[:idx] + patch + "\n" + s[idx:], encoding="utf-8")
print("[OK] patched", p)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "== smoke: /api/vsp/ui_status_v1 =="
curl -fsS "$BASE/api/vsp/ui_status_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"fails=",len(j.get("fails") or []))
for f in (j.get("fails") or [])[:6]:
    print(" -",f.get("check"),f.get("reason"),("err="+str(f.get("err")) if f.get("err") else ""))
PY

echo "[DONE]"
