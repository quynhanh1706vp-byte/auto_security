#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_always200_${TS}"
echo "[BACKUP] ${F}.bak_runs_always200_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_RUNS_ALWAYS200_WSGIMW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Append a last-layer WSGI MW that catches exceptions / non-200 and serves last-good cache as 200
inject = r'''

# --- VSP_P1_RUNS_ALWAYS200_WSGIMW_V1 ---
# Commercial hardening: /api/vsp/runs never flakes the UI. If downstream fails, serve last-good cache (200) + degraded headers.
import os, json, time, traceback

class _VspRunsAlways200MW:
    def __init__(self, app, cache_path):
        self.app = app
        self.cache_path = cache_path

    def _write_cache(self, body_bytes):
        try:
            os.makedirs(os.path.dirname(self.cache_path), exist_ok=True)
            with open(self.cache_path, "wb") as f:
                f.write(body_bytes)
        except Exception:
            pass

    def _read_cache(self):
        try:
            with open(self.cache_path, "rb") as f:
                return f.read()
        except Exception:
            return None

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs   = (environ.get("QUERY_STRING") or "")
        if not path.startswith("/api/vsp/runs"):
            return self.app(environ, start_response)

        info = {"path": path, "qs": qs}
        status_box = {}
        headers_box = {}

        def _sr(status, headers, exc_info=None):
            status_box["status"] = status
            headers_box["headers"] = list(headers or [])
            return start_response(status, headers, exc_info)

        try:
            chunks = []
            app_iter = self.app(environ, _sr)
            for c in app_iter:
                chunks.append(c)
            if hasattr(app_iter, "close"):
                try: app_iter.close()
                except Exception: pass

            body = b"".join(chunks)
            st = (status_box.get("status") or "500").split()[0]

            # If not 200 -> fallback to cache as 200 (degraded)
            if st != "200":
                cached = self._read_cache()
                if cached:
                    hdrs = [("Content-Type","application/json; charset=utf-8"),
                            ("Cache-Control","no-cache"),
                            ("X-VSP-RUNS-DEGRADED","1"),
                            ("X-VSP-RUNS-DEGRADED-REASON", f"status_{st}")]
                    start_response("200 OK", hdrs)
                    return [cached]
                # no cache => return minimal ok=true degraded payload
                payload = {"ok": True, "degraded": True, "reason": f"status_{st}", "items": [], "rid_latest": None, "ts": int(time.time())}
                b = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                hdrs = [("Content-Type","application/json; charset=utf-8"),
                        ("Cache-Control","no-cache"),
                        ("X-VSP-RUNS-DEGRADED","1"),
                        ("X-VSP-RUNS-DEGRADED-REASON", f"status_{st}")]
                start_response("200 OK", hdrs)
                return [b]

            # 200 OK => update cache and pass through
            self._write_cache(body)
            return [body]

        except Exception as e:
            cached = self._read_cache()
            if cached:
                hdrs = [("Content-Type","application/json; charset=utf-8"),
                        ("Cache-Control","no-cache"),
                        ("X-VSP-RUNS-DEGRADED","1"),
                        ("X-VSP-RUNS-DEGRADED-REASON","exception_cached")]
                start_response("200 OK", hdrs)
                return [cached]
            payload = {"ok": True, "degraded": True, "reason": "exception_no_cache", "error": str(e), "items": [], "rid_latest": None, "ts": int(time.time())}
            b = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            hdrs = [("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-cache"),
                    ("X-VSP-RUNS-DEGRADED","1"),
                    ("X-VSP-RUNS-DEGRADED-REASON","exception_no_cache")]
            start_response("200 OK", hdrs)
            return [b]

# Wrap last-layer (outside everything else)
try:
    _RUNS_CACHE_PATH = os.environ.get("VSP_RUNS_CACHE_PATH", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/runs_cache_last_good.json")
    application.wsgi_app = _VspRunsAlways200MW(application.wsgi_app, _RUNS_CACHE_PATH)
except Exception:
    pass
# --- /VSP_P1_RUNS_ALWAYS200_WSGIMW_V1 ---
'''
p.write_text(s + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] patch done. Now restart UI."
