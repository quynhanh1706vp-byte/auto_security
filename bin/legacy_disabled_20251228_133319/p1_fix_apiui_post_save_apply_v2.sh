#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need sort; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# 0) nếu file đang lỗi syntax -> restore từ backup gần nhất
if ! python3 -m py_compile "$W" >/dev/null 2>&1; then
  echo "[WARN] $W currently has SyntaxError -> trying restore from backups..."
  BAK="$(ls -1t ${W}.bak_apiui_post_* 2>/dev/null | head -n1 || true)"
  if [ -z "$BAK" ]; then
    BAK="$(ls -1t ${W}.bak_apiui_shim_* 2>/dev/null | head -n1 || true)"
  fi
  if [ -z "$BAK" ]; then
    BAK="$(ls -1t ${W}.bak_tabs3_bundle_fix1_* 2>/dev/null | head -n1 || true)"
  fi
  [ -n "$BAK" ] || { echo "[ERR] no suitable backup found to restore"; exit 2; }
  cp -f "$BAK" "$W"
  echo "[RESTORE] $BAK -> $W"
fi

cp -f "$W" "${W}.bak_fix_postwrap_${TS}"
echo "[BACKUP] ${W}.bak_fix_postwrap_${TS}"

mkdir -p out_ci/vsp_settings_v2 out_ci/rule_overrides_v2 out_ci/rule_overrides_v2/applied tools
[ -f tools/__init__.py ] || : > tools/__init__.py

python3 - <<'PY'
from pathlib import Path
import time, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_APIUI_POST_WRAPPER_P1_V2"
if MARK in s:
    print("[OK] wrapper already present, skip append")
    raise SystemExit(0)

append = r'''
# --- VSP_APIUI_POST_WRAPPER_P1_V2 ---
try:
    import json as __json, os as __os, time as __time
except Exception:
    __json = None
    __os = None
    __time = None

def __vsp__json(start_response, obj, code=200):
    try:
        body = (__json.dumps(obj, ensure_ascii=False, separators=(",",":")) if __json else str(obj)).encode("utf-8")
    except Exception:
        body = (str(obj)).encode("utf-8")
    status = f"{code} OK" if code < 400 else f"{code} ERROR"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Cache-Control", "no-store"),
        ("Content-Length", str(len(body))),
    ]
    start_response(status, headers)
    return [body]

def __vsp__read_body(environ):
    try:
        cl = int(environ.get("CONTENT_LENGTH") or "0")
    except Exception:
        cl = 0
    if cl <= 0:
        return b""
    w = environ.get("wsgi.input")
    if not w:
        return b""
    try:
        return w.read(cl) or b""
    except Exception:
        return b""

def __vsp__read_json(environ):
    raw = __vsp__read_body(environ)
    if not raw:
        return {}
    try:
        return __json.loads(raw.decode("utf-8", "replace")) if __json else {"_raw": raw.decode("utf-8","replace")}
    except Exception:
        return {"_raw": raw.decode("utf-8","replace")}

def __vsp__save_json(path, data):
    __os.makedirs(__os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        __json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    __os.replace(tmp, path)

def __vsp__wrap_post_only(orig):
    def _wsgi(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method != "POST" or not path.startswith("/api/ui/"):
                return orig(environ, start_response)

            # POST /api/ui/settings_v2  body: {settings:{...}} or {...}
            if path == "/api/ui/settings_v2":
                payload = __vsp__read_json(environ)
                settings = payload.get("settings") if isinstance(payload, dict) and "settings" in payload else payload
                if settings is None:
                    settings = {}
                out_path = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_settings_v2/settings.json"
                __vsp__save_json(out_path, settings if isinstance(settings, dict) else {"value": settings})
                return __vsp__json(start_response, {"ok": True, "path": out_path, "settings": settings, "ts": int(__time.time())})

            # POST /api/ui/rule_overrides_v2 body: {data:{rules:[...]}} or {rules:[...]} or {...}
            if path == "/api/ui/rule_overrides_v2":
                payload = __vsp__read_json(environ)
                if isinstance(payload, dict) and "data" in payload and isinstance(payload["data"], dict):
                    data = payload["data"]
                else:
                    data = payload if isinstance(payload, dict) else {}
                if "rules" not in data and isinstance(payload, dict) and "rules" in payload:
                    data = {"rules": payload.get("rules")}
                if "rules" not in data:
                    data = {"rules": []}
                out_path = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json"
                __vsp__save_json(out_path, data)
                return __vsp__json(start_response, {"ok": True, "path": out_path, "data": data, "ts": int(__time.time())})

            # POST /api/ui/rule_overrides_apply_v2 body: {rid:"..."} or query ?rid=...
            if path == "/api/ui/rule_overrides_apply_v2":
                payload = __vsp__read_json(environ)
                rid = None
                qs = environ.get("QUERY_STRING") or ""
                for kv in qs.split("&"):
                    if kv.startswith("rid="):
                        rid = kv.split("=", 1)[1]
                        break
                if not rid and isinstance(payload, dict):
                    rid = payload.get("rid") or payload.get("RID") or payload.get("run_id")
                if not rid:
                    return __vsp__json(start_response, {"ok": False, "error": "missing_rid", "ts": int(__time.time())}, 400)
                out_path = f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/applied/{rid}.json"
                __vsp__save_json(out_path, {"rid": rid, "applied_at": int(__time.time()), "payload": payload})
                return __vsp__json(start_response, {"ok": True, "rid": rid, "path": out_path, "ts": int(__time.time())})

            return __vsp__json(start_response, {"ok": False, "error": "not_found", "path": path, "ts": int(__time.time())}, 404)

        except Exception as e:
            return __vsp__json(start_response, {"ok": False, "error": "exception", "message": str(e), "ts": int(__time.time())}, 500)
    setattr(_wsgi, "__vsp_postwrap_v2", True)
    return _wsgi

# install wrapper (wrap Flask app.wsgi_app OR global application)
try:
    if "app" in globals() and hasattr(globals()["app"], "wsgi_app"):
        _orig = globals()["app"].wsgi_app
        if not getattr(_orig, "__vsp_postwrap_v2", False):
            globals()["app"].wsgi_app = __vsp__wrap_post_only(_orig)
    elif "application" in globals() and callable(globals()["application"]):
        _orig = globals()["application"]
        if not getattr(_orig, "__vsp_postwrap_v2", False):
            globals()["application"] = __vsp__wrap_post_only(_orig)
except Exception:
    pass
# --- END VSP_APIUI_POST_WRAPPER_P1_V2 ---
'''

p.write_text(s + "\n" + append, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1.0

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify POST endpoints (expect 200 ok:true) =="

curl -fsS -X POST "$BASE/api/ui/settings_v2" \
  -H "Content-Type: application/json" \
  -d '{"settings":{"degrade_graceful":true,"timeouts":{"kics_sec":900}}}' | head -c 220; echo

curl -fsS -X POST "$BASE/api/ui/rule_overrides_v2" \
  -H "Content-Type: application/json" \
  -d '{"data":{"rules":[]}}' | head -c 220; echo

RID="$(curl -fsS "$BASE/api/ui/runs_v2?limit=1" | python3 -c 'import sys, json; print(json.load(sys.stdin)["items"][0]["rid"])')"
curl -fsS -X POST "$BASE/api/ui/rule_overrides_apply_v2?rid=${RID}" \
  -H "Content-Type: application/json" \
  -d '{"rid":"'"$RID"'","note":"apply from ui"}' | head -c 220; echo

echo "[DONE] POST save/apply should be working now."
