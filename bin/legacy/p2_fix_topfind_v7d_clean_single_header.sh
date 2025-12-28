#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_v7d_${TS}"
echo "[BACKUP] ${W}.bak_topfind_v7d_${TS}"

# Cut everything from any VSP_P2_TOPFIND marker to EOF (strong cleanup)
python3 - "$W" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
m=re.search(r'(?m)^\s*#\s*===\s*VSP_P2_TOPFIND_.*$', s)
if m:
    s=s[:m.start()].rstrip()+"\n\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] truncated from first VSP_P2_TOPFIND marker to EOF")
else:
    print("[OK] no VSP_P2_TOPFIND marker found; keep file as-is")
PY

cat >> "$W" <<'PY'

# === VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7D ===
# Proper WSGI middleware: capture status/headers WITHOUT calling start_response,
# then call start_response ONCE with corrected headers + replay full body.
import os, json, urllib.request, urllib.parse, time

_V7D_MARKER = "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7D"

def _qs_get(qs: str, key: str) -> str:
    try:
        d = urllib.parse.parse_qs(qs, keep_blank_values=True)
        v = d.get(key)
        return (v[0] if v else "") or ""
    except Exception:
        return ""

def _qs_set(qs: str, key: str, val: str) -> str:
    d = urllib.parse.parse_qs(qs, keep_blank_values=True)
    d[key] = [val]
    return urllib.parse.urlencode(d, doseq=True)

def _fetch_rid_latest(base: str, timeout: float = 0.8) -> str:
    try:
        url = base.rstrip("/") + "/api/vsp/rid_latest"
        req = urllib.request.Request(url, headers={"Accept":"application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            b = r.read() or b""
        j = json.loads(b.decode("utf-8", "replace") or "{}")
        return (j.get("rid") or "").strip()
    except Exception:
        return ""

class _VSPTopFindV7DMiddleware:
    def __init__(self, app, base: str):
        self.app = app
        self.base = base.rstrip("/")
        self._cache_rid = ""
        self._cache_ts = 0.0

    def _rid_latest_cached(self) -> str:
        now = time.time()
        if self._cache_rid and (now - self._cache_ts) < 2.0:
            return self._cache_rid
        rid = _fetch_rid_latest(self.base)
        if rid:
            self._cache_rid = rid
            self._cache_ts = now
        return rid

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = (environ.get("QUERY_STRING") or "")

        # Force rid_latest if missing
        if path == "/api/vsp/top_findings_v1" and not _qs_get(qs, "rid"):
            rid_latest = self._rid_latest_cached()
            if rid_latest:
                environ["QUERY_STRING"] = _qs_set(qs, "rid", rid_latest)

        captured = {"status": None, "headers": None, "exc": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            # Return a dummy write callable (rarely used)
            return (lambda x: None)

        app_iter = self.app(environ, _sr)

        body_chunks = []
        try:
            for chunk in app_iter:
                if chunk:
                    body_chunks.append(chunk)
        finally:
            try:
                close = getattr(app_iter, "close", None)
                if callable(close): close()
            except Exception:
                pass

        body = b"".join(body_chunks)

        status = captured["status"] or "200 OK"
        hdrs = captured["headers"] or []

        if path == "/api/vsp/top_findings_v1":
            # Remove all previous X-VSP header duplicates
            hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "x-vsp-topfind-runid-fix"]

            # Patch JSON if needed
            try:
                if body and body.lstrip()[:1] == b"{":
                    j = json.loads(body.decode("utf-8","replace"))
                    if isinstance(j, dict):
                        if j.get("ok") is True and (j.get("run_id") is None or j.get("run_id") == ""):
                            rid_used = j.get("rid_used") or _qs_get(environ.get("QUERY_STRING",""), "rid")
                            if rid_used:
                                j["run_id"] = rid_used
                                j["marker"] = _V7D_MARKER
                                body = json.dumps(j, ensure_ascii=False).encode("utf-8")
            except Exception:
                pass

            # Set single marker header
            hdrs.append(("X-VSP-TOPFIND-RUNID-FIX", "ok-v7d"))

            # Fix Content-Length
            hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "content-length"]
            hdrs.append(("Content-Length", str(len(body))))

        start_response(status, hdrs, captured["exc"])
        return [body]

# Wrap final target
try:
    _base = os.environ.get("VSP_UI_BASE", "http://127.0.0.1:8910")
    _t = globals().get("application") or globals().get("app")
    if _t:
        globals()["application"] = _VSPTopFindV7DMiddleware(_t, _base)
        globals()["app"] = globals()["application"]
except Exception:
    pass
# === END V7D ===
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== PROOF headers (HEAD) =="
curl --http1.1 -sSI "$BASE/api/vsp/top_findings_v1?limit=1" \
 | egrep -i 'http/|content-type|content-length|x-vsp-topfind-runid-fix' || true

echo "== PROOF parse JSON =="
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; raw=sys.stdin.read(); print("raw_len=",len(raw)); j=json.loads(raw); print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"),"marker=",j.get("marker"),"total=",j.get("total"))'
