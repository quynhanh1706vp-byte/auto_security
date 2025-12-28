#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_runfile_contract_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUN_FILE_ALLOW_FORCE_JSON_CONTRACT_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# ===================== VSP_P1_RUN_FILE_ALLOW_FORCE_JSON_CONTRACT_V1 =====================
import json as _vsp__json
from urllib.parse import parse_qs as _vsp__parse_qs

# wrap current WSGI callable named `application` (or `app`), and re-bind exports at the end
_vsp__inner_app = None
if "application" in globals() and callable(globals().get("application")):
    _vsp__inner_app = globals()["application"]
elif "app" in globals() and callable(globals().get("app")):
    _vsp__inner_app = globals()["app"]

def _vsp__emit_json(start_response, obj):
    b = _vsp__json.dumps(obj, ensure_ascii=False).encode("utf-8")
    start_response("200 OK", [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(b))),
    ])
    return [b]

def _vsp__force_json_contract_run_file_allow(environ, start_response):
    path = environ.get("PATH_INFO", "") or ""
    if path != "/api/vsp/run_file_allow" or _vsp__inner_app is None:
        return _vsp__inner_app(environ, start_response)

    cap = {}
    def _sr(status, headers, exc_info=None):
        cap["status"] = status
        cap["headers"] = headers or []
        cap["exc_info"] = exc_info
        def _write(_data):  # rarely used
            return None
        return _write

    it = _vsp__inner_app(environ, _sr)
    try:
        body = b"".join(it) if it is not None else b""
    finally:
        try:
            close = getattr(it, "close", None)
            if callable(close): close()
        except Exception:
            pass

    status_line = cap.get("status", "200 OK")
    try:
        http = int(str(status_line).split()[0])
    except Exception:
        http = 200

    headers = cap.get("headers", []) or []
    ct = ""
    for k, v in headers:
        if str(k).lower() == "content-type":
            ct = str(v); break

    qs = environ.get("QUERY_STRING", "") or ""
    q = _vsp__parse_qs(qs, keep_blank_values=True)
    rid = (q.get("rid", [""]) or [""])[0]
    req_path = (q.get("path", [""]) or [""])[0]

    # empty / non-json / invalid json => emit contract JSON
    if (not body) or ("application/json" not in (ct or "").lower()):
        return _vsp__emit_json(start_response, {
            "ok": False, "http": http,
            "err": "non-json or empty response",
            "rid": rid, "path": req_path,
            "allow": [],
        })

    try:
        _vsp__json.loads(body.decode("utf-8", errors="replace"))
    except Exception:
        return _vsp__emit_json(start_response, {
            "ok": False, "http": http,
            "err": "invalid json from backend",
            "rid": rid, "path": req_path,
            "allow": [],
        })

    # body is valid json => normalize headers + always 200
    start_response("200 OK", [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(body))),
    ])
    return [body]

# rebind WSGI entrypoints
application = _vsp__force_json_contract_run_file_allow
app = application
# ===================== /VSP_P1_RUN_FILE_ALLOW_FORCE_JSON_CONTRACT_V1 =====================
''').rstrip() + "\n"

# append at end (safe even if app=application existed earlier)
s2 = s + ("\n" if not s.endswith("\n") else "") + block
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl not found; restart service manually if needed."
fi

echo "[DONE] run_file_allow forced JSON contract at WSGI layer"
