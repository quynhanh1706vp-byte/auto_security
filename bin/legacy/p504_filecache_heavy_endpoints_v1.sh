#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || T="vsp_demo_app.py"
[ -f "$T" ] || { echo "[ERR] missing wsgi_vsp_ui_gateway.py and vsp_demo_app.py"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p504_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] target=$T backup=$OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY' "$T"
from pathlib import Path
import sys, re
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P504_FILECACHE_HEAVY_ENDPOINTS_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet = r'''
# VSP_P504_FILECACHE_HEAVY_ENDPOINTS_V1
# Shared (multi-worker) file cache for heavy JSON endpoints.
import os, time, hashlib

class _VSPFileCacheHeavyV1:
    def __init__(self, app, ttl=15.0, cache_dir="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/p504_fcache", max_body=3_000_000):
        self.app = app
        self.ttl = float(ttl)
        self.cache_dir = cache_dir
        self.max_body = int(max_body)
        self.cache_paths = set([
            "/api/vsp/top_findings_v2",
            "/api/vsp/rule_overrides",
            "/api/vsp/overrides",
            "/api/vsp/run_file_allow",
        ])
        try:
            os.makedirs(self.cache_dir, exist_ok=True)
        except Exception:
            pass

    def _key(self, method, path, qs):
        h = hashlib.sha256(f"{method}|{path}|{qs}".encode("utf-8","replace")).hexdigest()
        return h

    def _paths(self, k):
        meta = os.path.join(self.cache_dir, k + ".meta")
        body = os.path.join(self.cache_dir, k + ".body")
        return meta, body

    def _fresh(self, meta_path):
        try:
            return (time.time() - os.path.getmtime(meta_path)) <= self.ttl
        except Exception:
            return False

    def _read(self, meta_path, body_path):
        try:
            meta = open(meta_path, "r", encoding="utf-8", errors="replace").read().splitlines()
            status = meta[0] if meta else "200 OK"
            ct = meta[1] if len(meta) > 1 else "application/json; charset=utf-8"
            b = open(body_path, "rb").read()
            return status, ct, b
        except Exception:
            return None

    def _write_atomic(self, meta_path, body_path, status, ct, body):
        try:
            tmpm = meta_path + ".tmp"
            tmpb = body_path + ".tmp"
            with open(tmpm, "w", encoding="utf-8") as f:
                f.write((status or "200 OK") + "\n")
                f.write((ct or "application/json; charset=utf-8") + "\n")
            with open(tmpb, "wb") as f:
                f.write(body)
            os.replace(tmpm, meta_path)
            os.replace(tmpb, body_path)
        except Exception:
            pass

    def __call__(self, environ, start_response):
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        path = environ.get("PATH_INFO") or ""
        qs = environ.get("QUERY_STRING") or ""

        if method == "GET" and path in self.cache_paths:
            k = self._key(method, path, qs)
            meta_path, body_path = self._paths(k)
            if self._fresh(meta_path) and os.path.exists(body_path):
                ent = self._read(meta_path, body_path)
                if ent:
                    status, ct, body = ent
                    headers = [
                        ("Content-Type", ct),
                        ("Content-Length", str(len(body))),
                        ("X-VSP-P504-FCACHE", "HIT"),
                        ("Cache-Control", "no-store"),
                    ]
                    start_response(status, headers)
                    return [body]

        # MISS: capture downstream response safely
        captured = {"status":"200 OK","headers":[],"exc":None}
        write_buf = []

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            def _write(data):
                if data:
                    write_buf.append(data if isinstance(data,(bytes,bytearray)) else str(data).encode("utf-8","replace"))
            return _write

        it = None
        try:
            it = self.app(environ, _sr)
            body = b"".join(write_buf + list(it or []))
        finally:
            try:
                if hasattr(it, "close"): it.close()
            except Exception:
                pass

        status = captured["status"]
        headers = captured["headers"]

        # try persist if heavy + ok + json + small
        try:
            if method == "GET" and path in self.cache_paths and status.startswith("200") and len(body) <= self.max_body:
                ct = ""
                for k,v in headers:
                    if (k or "").lower() == "content-type":
                        ct = v or ""
                        break
                if "application/json" in (ct or ""):
                    k2 = self._key(method, path, qs)
                    meta_path, body_path = self._paths(k2)
                    self._write_atomic(meta_path, body_path, status, ct, body)
        except Exception:
            pass

        # return as-is but stamp MISS if heavy endpoint
        try:
            if method == "GET" and path in self.cache_paths:
                headers = [h for h in headers if (h[0] or "").lower() != "x-vsp-p504-fcache"]
                headers.append(("X-VSP-P504-FCACHE", "MISS"))
        except Exception:
            pass

        start_response(status, headers, captured.get("exc"))
        return [body]

def _vsp_p504_wrap(app_obj):
    try:
        if hasattr(app_obj, "wsgi_app"):
            app_obj.wsgi_app = _VSPFileCacheHeavyV1(app_obj.wsgi_app, ttl=15.0)
            return app_obj
    except Exception:
        pass
    try:
        if callable(app_obj):
            return _VSPFileCacheHeavyV1(app_obj, ttl=15.0)
    except Exception:
        pass
    return app_obj

try:
    if "app" in globals():
        globals()["app"] = _vsp_p504_wrap(globals()["app"])
    if "application" in globals():
        globals()["application"] = _vsp_p504_wrap(globals()["application"])
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
echo "[OK] patched. Restart service now."
