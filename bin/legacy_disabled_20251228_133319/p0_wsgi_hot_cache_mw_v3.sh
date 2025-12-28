#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_hotcache_${TS}"
echo "[BACKUP] ${WSGI}.bak_hotcache_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_HOT_CACHE_MW_V3"

if marker in s:
    print("[OK] marker already present:", marker)
else:
    block = r'''
# ===================== VSP_P0_HOT_CACHE_MW_V3 =====================
# WSGI-level micro cache for hot GET endpoints to keep dashboard live polling snappy.
# Rationale: app is wrapped (not always Flask-mountable), so cache at outermost WSGI.
import time as _vsp_time
import threading as _vsp_threading

class _VSPHotCacheWSGI:
    def __init__(self, app, ttl=4.0, max_items=128, max_bytes=256*1024):
        self.app = app
        self.ttl = float(ttl)
        self.max_items = int(max_items)
        self.max_bytes = int(max_bytes)
        self._lock = _vsp_threading.Lock()
        # key -> (exp_ts, status, headers_list, body_bytes)
        self._cache = {}

        # hot endpoints (PATH_INFO). Query string is part of cache key automatically.
        self._hot_paths = {
            "/api/vsp/rid_latest_gate_root",
            "/api/vsp/rid_latest",
            "/api/vsp/runs",
            "/api/vsp/run_file_allow",
        }

    def _is_cacheable(self, environ):
        if environ.get("REQUEST_METHOD", "GET") != "GET":
            return False
        path = environ.get("PATH_INFO") or ""
        if path not in self._hot_paths:
            return False

        # Avoid caching very large payloads (findings_unified.json can be >1MB)
        qs = (environ.get("QUERY_STRING") or "").lower()
        if path == "/api/vsp/run_file_allow":
            # only cache small JSONs
            if "path=run_gate_summary.json" in qs or "path=run_gate.json" in qs:
                return True
            return False

        # /api/vsp/runs can be a bit large but usually still OK; keep it.
        return True

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO") or ""
            qs = environ.get("QUERY_STRING") or ""
            key = path + ("?" + qs if qs else "")

            if not self._is_cacheable(environ):
                return self.app(environ, start_response)

            now = _vsp_time.time()
            with self._lock:
                hit = self._cache.get(key)
                if hit and hit[0] >= now:
                    status, headers, body = hit[1], hit[2], hit[3]
                    start_response(status, headers)
                    return [body]

            # miss: capture downstream response
            captured = {"status": "200 OK", "headers": []}
            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers or [])
                return start_response(status, headers, exc_info)

            it = self.app(environ, _sr)
            body = b""
            try:
                for chunk in it:
                    if chunk:
                        body += chunk
                        if len(body) > self.max_bytes:
                            # too big, do not cache
                            return [body] + list(it)
            finally:
                if hasattr(it, "close"):
                    try: it.close()
                    except Exception: pass

            # store
            with self._lock:
                if len(self._cache) >= self.max_items:
                    # drop oldest expiring
                    k_old = min(self._cache.items(), key=lambda kv: kv[1][0])[0]
                    self._cache.pop(k_old, None)
                self._cache[key] = (now + self.ttl, captured["status"], captured["headers"], body)

            return [body]

        except Exception:
            # fail-open
            return self.app(environ, start_response)

# Wrap outermost WSGI entrypoint if present.
try:
    if "application" in globals() and callable(globals().get("application")):
        application = _VSPHotCacheWSGI(application, ttl=4.0, max_items=128, max_bytes=256*1024)
        try:
            print("[VSP_P0_HOT_CACHE_MW_V3] wrapped application (ttl=4s)")
        except Exception:
            pass
except Exception:
    pass
# ===================== /VSP_P0_HOT_CACHE_MW_V3 =====================
'''
    s2 = s.rstrip() + "\n\n" + block.strip() + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 1

echo "== smoke timing (expect call #2/#3 much faster due to cache per-worker) =="
for i in 1 2 3; do
  curl -fsS -o /dev/null -w "rid_latest_gate_root i=$i status=%{http_code} t=%{time_total}\n" "$BASE/api/vsp/rid_latest_gate_root"
done
for i in 1 2 3; do
  curl -fsS -o /dev/null -w "runs(limit=10) i=$i status=%{http_code} t=%{time_total}\n" "$BASE/api/vsp/runs?limit=10"
done

echo "[DONE] Hard reload: Ctrl+Shift+R on $BASE/vsp5"
