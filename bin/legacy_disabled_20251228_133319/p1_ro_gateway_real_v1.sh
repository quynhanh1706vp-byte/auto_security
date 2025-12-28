#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_ro_gw_real_${TS}"
echo "[BACKUP] ${W}.bak_ro_gw_real_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_RO_WSGI_REAL_V1" in s:
    print("[OK] already patched (VSP_RO_WSGI_REAL_V1)")
    raise SystemExit(0)

# Ensure imports exist (best-effort, safe if duplicated)
need_imports = ["import json", "from pathlib import Path"]
ins = 0
for m in re.finditer(r"(?m)^(import .+|from .+ import .+)\s*$", s):
    ins = m.end()

prepend = ""
for imp in need_imports:
    if imp not in s:
        prepend += imp + "\n"

s = prepend + s

# Append a WSGI wrapper around `application` (whatever it currently is)
patch = r'''
# ===== VSP_RO_WSGI_REAL_V1: rule_overrides_v1 real-but-safe at gateway =====
try:
    _vsp_ro_old_application = application
except Exception:
    _vsp_ro_old_application = None

_VSP_RO_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides")
_VSP_RO_FILE = _VSP_RO_DIR / "rule_overrides_v1.json"

def _vsp_ro_resp(start_response, payload: dict):
    body = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("X-VSP-RO-SAFE", "1" if payload.get("degraded") else "0"),
        ("Cache-Control", "no-store"),
    ]
    start_response("200 OK", headers)
    return [body]

def _vsp_ro_load():
    try:
        _VSP_RO_DIR.mkdir(parents=True, exist_ok=True)
        if _VSP_RO_FILE.exists():
            return json.loads(_VSP_RO_FILE.read_text(encoding="utf-8"))
        return {"ok": True, "degraded": False, "items": []}
    except Exception as e:
        return {"ok": True, "degraded": True, "items": [], "note": "degraded-safe", "error": str(e)}

def _vsp_ro_save(obj):
    try:
        _VSP_RO_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _VSP_RO_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(_VSP_RO_FILE)
        return True, None
    except Exception as e:
        return False, str(e)

def application(environ, start_response):
    try:
        path = environ.get("PATH_INFO", "") or ""
        if path == "/api/vsp/rule_overrides_v1":
            method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
            if method == "GET":
                return _vsp_ro_resp(start_response, _vsp_ro_load())

            if method in ("POST", "PUT"):
                # read request body (best-effort)
                try:
                    ln = int(environ.get("CONTENT_LENGTH") or "0")
                except Exception:
                    ln = 0
                raw = b""
                if ln > 0:
                    raw = environ["wsgi.input"].read(ln) or b""
                try:
                    payload = json.loads(raw.decode("utf-8") or "{}") if raw else {}
                except Exception as e:
                    payload = {}
                items = payload.get("items", payload.get("rules", payload.get("overrides")))
                if items is None:
                    items = payload.get("data", [])
                if not isinstance(items, list):
                    items = []
                out = {"ok": True, "degraded": False, "items": items}
                ok, err = _vsp_ro_save(out)
                if not ok:
                    out["degraded"] = True
                    out["note"] = "persist failed; degraded-safe"
                    out["error"] = err
                return _vsp_ro_resp(start_response, out)

            # unknown method => still never-500
            return _vsp_ro_resp(start_response, {"ok": True, "degraded": True, "items": [], "note": f"method {method} not supported"})
    except Exception as e:
        return _vsp_ro_resp(start_response, {"ok": True, "degraded": True, "items": [], "note": "exception; degraded-safe", "error": str(e)})

    # fallthrough
    if _vsp_ro_old_application:
        return _vsp_ro_old_application(environ, start_response)
    start_response("500 Internal Server Error", [("Content-Type","text/plain")])
    return [b"no application"]
# ===== end VSP_RO_WSGI_REAL_V1 =====
'''

s = s.rstrip() + "\n\n" + patch + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended gateway RO wrapper")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== probe GET (expect degraded true/false, header X-VSP-RO-SAFE) =="
curl -i -sS "$BASE/api/vsp/rule_overrides_v1" | head -n 40

echo "== probe WRITE (PUT) =="
curl -sS -X PUT -H 'content-type: application/json' \
  -d '{"items":[{"id":"p1-test","action":"allow","note":"gateway ro real"}]}' \
  "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j)'

echo "== probe GET after WRITE =="
curl -sS "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("degraded=",j.get("degraded"),"items=",j.get("items"))'
