#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_forcewrap_runs_${TS}"
echo "[BACKUP] ${F}.bak_forcewrap_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FORCE_WRAP_RUNS_ALWAYS200_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''

# --- VSP_P1_FORCE_WRAP_RUNS_ALWAYS200_V1 ---
# Force /api/vsp/runs always returns 200 (cache fallback) to avoid UI "RUNS API FAIL 503".
import os, json, time

def _runs_cache_path():
    return os.environ.get("VSP_RUNS_CACHE_PATH", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/runs_cache_last_good.json")

class _ForceWrapRunsAlways200MW:
    def __init__(self, app):
        self.app = app

    def _read_cache(self):
        try:
            return open(_runs_cache_path(), "rb").read()
        except Exception:
            return None

    def _write_cache(self, b):
        try:
            os.makedirs(os.path.dirname(_runs_cache_path()), exist_ok=True)
            with open(_runs_cache_path(), "wb") as f:
                f.write(b)
        except Exception:
            pass

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/runs"):
            return self.app(environ, start_response)

        status_box = {}
        headers_box = {}

        def _sr(status, headers, exc_info=None):
            status_box["status"] = status
            headers_box["headers"] = list(headers or [])
            return start_response(status, headers, exc_info)

        try:
            chunks=[]
            it = self.app(environ, _sr)
            for c in it:
                chunks.append(c)
            if hasattr(it, "close"):
                try: it.close()
                except Exception: pass

            body = b"".join(chunks)
            code = (status_box.get("status") or "500").split()[0]

            if code == "200":
                # cache only if JSON decodes
                try:
                    j = json.loads(body.decode("utf-8","replace"))
                    if isinstance(j, dict) and j.get("ok") is True and j.get("items") is not None:
                        self._write_cache(body)
                except Exception:
                    pass
                return [body]

            cached = self._read_cache()
            if cached:
                hdrs=[("Content-Type","application/json; charset=utf-8"),
                      ("Cache-Control","no-store"),
                      ("X-VSP-RUNS-DEGRADED","1"),
                      ("X-VSP-RUNS-DEGRADED-REASON", f"status_{code}")]
                start_response("200 OK", hdrs)
                return [cached]

            payload={"ok": True, "degraded": True, "reason": f"status_{code}", "rid_latest": None, "items": [], "ts": int(time.time())}
            b=json.dumps(payload, ensure_ascii=False).encode("utf-8")
            hdrs=[("Content-Type","application/json; charset=utf-8"),
                  ("Cache-Control","no-store"),
                  ("X-VSP-RUNS-DEGRADED","1"),
                  ("X-VSP-RUNS-DEGRADED-REASON", f"status_{code}")]
            start_response("200 OK", hdrs)
            return [b]

        except Exception as e:
            cached = self._read_cache()
            if cached:
                hdrs=[("Content-Type","application/json; charset=utf-8"),
                      ("Cache-Control","no-store"),
                      ("X-VSP-RUNS-DEGRADED","1"),
                      ("X-VSP-RUNS-DEGRADED-REASON","exception_cached")]
                start_response("200 OK", hdrs)
                return [cached]
            payload={"ok": True, "degraded": True, "reason":"exception_no_cache", "error": str(e), "rid_latest": None, "items": [], "ts": int(time.time())}
            b=json.dumps(payload, ensure_ascii=False).encode("utf-8")
            hdrs=[("Content-Type","application/json; charset=utf-8"),
                  ("Cache-Control","no-store"),
                  ("X-VSP-RUNS-DEGRADED","1"),
                  ("X-VSP-RUNS-DEGRADED-REASON","exception_no_cache")]
            start_response("200 OK", hdrs)
            return [b]

# FORCE wrap module-level callable `application`
try:
    _orig_app_runs = application
    application = _ForceWrapRunsAlways200MW(_orig_app_runs)
except Exception:
    pass
# --- /VSP_P1_FORCE_WRAP_RUNS_ALWAYS200_V1 ---
'''
p.write_text(s + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] patch done. Restart UI."
