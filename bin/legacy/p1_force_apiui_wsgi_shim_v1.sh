#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_apiui_shim_${TS}"
echo "[BACKUP] ${W}.bak_apiui_shim_${TS}"

mkdir -p tools
[ -f tools/__init__.py ] || : > tools/__init__.py

python3 - <<'PY'
from pathlib import Path
import time, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_APIUI_WSGI_SHIM_V1"
if marker in s:
    print("[OK] shim already present")
    raise SystemExit(0)

append = r'''
# ============================================================
# VSP_P1_APIUI_WSGI_SHIM_V1
# WSGI-level /api/ui/* handler (robust even if Flask routes can't be added)
# Endpoints:
#  - GET  /api/ui/runs_v2?limit=...
#  - GET  /api/ui/findings_v2?rid=&limit=&offset=&q=&tool=&severity=
#  - GET  /api/ui/settings_v2
#  - POST /api/ui/settings_v2   (json body)
#  - GET  /api/ui/rule_overrides_v2
#  - POST /api/ui/rule_overrides_v2 (json body)
#  - POST /api/ui/rule_overrides_apply_v2 (json body {rid})
# ============================================================
def _vsp__json_bytes(obj):
    import json
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")

def _vsp__read_body(environ):
    try:
        n = int(environ.get("CONTENT_LENGTH") or "0")
    except Exception:
        n = 0
    if n <= 0:
        return b""
    try:
        return environ["wsgi.input"].read(n)  # type: ignore
    except Exception:
        return b""

def _vsp__parse_qs(environ):
    try:
        from urllib.parse import parse_qs
        return parse_qs(environ.get("QUERY_STRING","") or "")
    except Exception:
        return {}

def _vsp__qs_get(qs, k, default=""):
    v = qs.get(k)
    if not v:
        return default
    return v[0] if isinstance(v, list) else str(v)

def _vsp__qs_int(qs, k, default):
    try:
        return int(_vsp__qs_get(qs, k, str(default)))
    except Exception:
        return default

def _vsp__apiui_handle(environ):
    import json, time
    path = environ.get("PATH_INFO","") or ""
    method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
    try:
        from tools import vsp_tabs3_api_impl_v1 as _impl
    except Exception as e:
        return 500, {"ok": False, "error": "IMPL_IMPORT_FAILED", "detail": str(e), "path": path, "ts": int(time.time())}

    qs = _vsp__parse_qs(environ)

    if path == "/api/ui/runs_v2":
        if method != "GET":
            return 405, {"ok": False, "error": "METHOD_NOT_ALLOWED", "path": path, "ts": int(time.time())}
        limit = _vsp__qs_int(qs, "limit", 50)
        return 200, _impl.list_runs(limit=limit)

    if path == "/api/ui/findings_v2":
        if method != "GET":
            return 405, {"ok": False, "error": "METHOD_NOT_ALLOWED", "path": path, "ts": int(time.time())}
        rid = _vsp__qs_get(qs, "rid", "") or None
        limit = _vsp__qs_int(qs, "limit", 50)
        offset = _vsp__qs_int(qs, "offset", 0)
        q = _vsp__qs_get(qs, "q", "")
        tool = _vsp__qs_get(qs, "tool", "")
        severity = _vsp__qs_get(qs, "severity", "ALL")
        return 200, _impl.findings_query(rid=rid, limit=limit, offset=offset, q=q, tool=tool, severity=severity)

    if path == "/api/ui/settings_v2":
        if method == "GET":
            return 200, _impl.settings_get()
        if method == "POST":
            raw = _vsp__read_body(environ)
            try:
                obj = json.loads(raw.decode("utf-8","replace") or "{}")
            except Exception:
                obj = {}
            return 200, _impl.settings_save(obj)
        return 405, {"ok": False, "error": "METHOD_NOT_ALLOWED", "path": path, "ts": int(time.time())}

    if path == "/api/ui/rule_overrides_v2":
        if method == "GET":
            return 200, _impl.rules_get()
        if method == "POST":
            raw = _vsp__read_body(environ)
            try:
                obj = json.loads(raw.decode("utf-8","replace") or "{}")
            except Exception:
                obj = {}
            return 200, _impl.rules_save(obj)
        return 405, {"ok": False, "error": "METHOD_NOT_ALLOWED", "path": path, "ts": int(time.time())}

    if path == "/api/ui/rule_overrides_apply_v2":
        if method != "POST":
            return 405, {"ok": False, "error": "METHOD_NOT_ALLOWED", "path": path, "ts": int(time.time())}
        raw = _vsp__read_body(environ)
        try:
            obj = json.loads(raw.decode("utf-8","replace") or "{}")
        except Exception:
            obj = {}
        rid = str(obj.get("rid") or "")
        return 200, _impl.rules_apply_to_rid(rid)

    return 404, {"ok": False, "error": "HTTP_404_NOT_FOUND", "path": path, "ts": int(time.time())}

def _vsp__wrap_wsgi(orig_app):
    def _shim(environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path.startswith("/api/ui/"):
            status, payload = _vsp__apiui_handle(environ)
            body = _vsp__json_bytes(payload)
            hdrs = [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-store"),
                ("Content-Length", str(len(body))),
            ]
            start_response(f"{status} OK" if status == 200 else f"{status} ERROR", hdrs)
            return [body]
        return orig_app(environ, start_response)
    return _shim

# Try wrap `application` first, else wrap `app.wsgi_app`
try:
    application  # noqa
    application = _vsp__wrap_wsgi(application)  # type: ignore
except Exception:
    try:
        app.wsgi_app = _vsp__wrap_wsgi(app.wsgi_app)  # type: ignore
    except Exception:
        pass
# ============================================================
'''

p.write_text(s + "\n" + append, encoding="utf-8")
print("[OK] appended WSGI shim")
PY

echo "== py_compile =="
python3 -m py_compile tools/vsp_tabs3_api_impl_v1.py
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.9

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify /api/ui now 200 JSON =="
curl -fsS "$BASE/api/ui/runs_v2?limit=1" | head -c 260; echo
curl -fsS "$BASE/api/ui/findings_v2?limit=1&offset=0" | head -c 260; echo
curl -fsS "$BASE/api/ui/settings_v2" | head -c 260; echo
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 260; echo

echo "[DONE] api/ui shim installed"
