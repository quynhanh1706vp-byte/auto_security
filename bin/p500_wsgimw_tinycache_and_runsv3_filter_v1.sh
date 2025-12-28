#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || T="vsp_demo_app.py"
[ -f "$T" ] || { echo "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p500_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] target=$T backup=$OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY' "$T"
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P500_TINYCACHE_AND_RUNSV3_FILTER_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

snippet = r'''
# VSP_P500_TINYCACHE_AND_RUNSV3_FILTER_V1
# - tiny in-memory TTL cache for heavy GET endpoints
# - filter out selfcheck runs (rid/run_id prefix p49*/p490*) from runs_v3 JSON
try:
    import time, json
except Exception:
    time = None
    json = None

class _VSPTinyCacheV1:
    def __init__(self, app, ttl=2.0):
        self.app = app
        self.ttl = float(ttl)
        self._cache = {}  # key -> (ts, status, headers, body_bytes)

        self.cache_paths = set([
            "/api/vsp/top_findings_v2",
            "/api/vsp/rule_overrides",
            "/api/vsp/overrides",
            "/api/vsp/run_file_allow",
        ])

    def _now(self):
        return time.time() if time else 0.0

    def _start_response_capture(self, start_response, box):
        def _sr(status, headers, exc_info=None):
            box["status"] = status
            box["headers"] = list(headers or [])
            return start_response(status, headers, exc_info)
        return _sr

    def _hdr_get(self, headers, name):
        n = name.lower()
        for k,v in headers:
            if (k or "").lower() == n:
                return v
        return ""

    def _hdr_set(self, headers, name, value):
        n = name.lower()
        out=[]
        found=False
        for k,v in headers:
            if (k or "").lower() == n:
                out.append((k, value))
                found=True
            else:
                out.append((k,v))
        if not found:
            out.append((name, value))
        return out

    def _maybe_filter_runs_v3(self, path, headers, body):
        if json is None:
            return headers, body
        if path != "/api/vsp/runs_v3":
            return headers, body
        ct = self._hdr_get(headers, "Content-Type") or ""
        if "application/json" not in ct:
            return headers, body
        try:
            obj = json.loads(body.decode("utf-8", "replace"))
            if not isinstance(obj, dict):
                return headers, body

            def _keep(x):
                if not isinstance(x, dict):
                    return True
                rid = (x.get("rid") or x.get("run_id") or "").strip()
                # drop selfcheck/ops runs
                return not (rid.startswith("p49") or rid.startswith("p490"))

            for k in ("runs", "items"):
                if isinstance(obj.get(k), list):
                    obj[k] = [x for x in obj[k] if _keep(x)]

            # keep total as-is (historical) OR adjust? -> adjust to len(runs) for UI sanity if present
            if isinstance(obj.get("runs"), list):
                obj["total"] = obj.get("total", len(obj["runs"]))
            body2 = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            headers2 = self._hdr_set(headers, "Content-Length", str(len(body2)))
            return headers2, body2
        except Exception:
            return headers, body

    def __call__(self, environ, start_response):
        try:
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            path = environ.get("PATH_INFO") or ""
            qs = environ.get("QUERY_STRING") or ""
            key = (method, path, qs)

            # only cache selected GET
            if method == "GET" and path in self.cache_paths:
                ent = self._cache.get(key)
                if ent:
                    ts, status, headers, body = ent
                    if self._now() - ts <= self.ttl:
                        headers = self._hdr_set(headers, "X-VSP-P500-CACHE", "HIT")
                        start_response(status, headers)
                        return [body]

            box = {}
            sr = self._start_response_capture(start_response, box)
            it = self.app(environ, sr)
            body = b"".join(it) if it is not None else b""
            status = box.get("status", "200 OK")
            headers = box.get("headers", [])
            # filter runs_v3 selfcheck
            headers, body = self._maybe_filter_runs_v3(path, headers, body)

            if method == "GET" and path in self.cache_paths:
                headers = self._hdr_set(headers, "X-VSP-P500-CACHE", "MISS")
                self._cache[key] = (self._now(), status, headers, body)

            # ensure content-length is correct when we rebuild body
            headers = self._hdr_set(headers, "Content-Length", str(len(body)))
            start_response(status, headers)
            return [body]
        except Exception:
            return self.app(environ, start_response)

def _vsp_p500_wrap(app_obj):
    # Flask app -> wrap wsgi_app; WSGI callable -> wrap itself
    try:
        if hasattr(app_obj, "wsgi_app"):
            app_obj.wsgi_app = _VSPTinyCacheV1(app_obj.wsgi_app, ttl=2.0)
            return app_obj
    except Exception:
        pass
    try:
        if callable(app_obj):
            return _VSPTinyCacheV1(app_obj, ttl=2.0)
    except Exception:
        pass
    return app_obj

# try wrap common globals
try:
    if "app" in globals():
        globals()["app"] = _vsp_p500_wrap(globals()["app"])
    if "application" in globals():
        globals()["application"] = _vsp_p500_wrap(globals()["application"])
except Exception:
    pass
'''

# append at end (safe)
s2 = s.rstrip() + "\n\n" + snippet + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[OK] patched. Now restart service to take effect."
echo "[TIP] After restart, heavy endpoints should show header: X-VSP-P500-CACHE: HIT/MISS"
