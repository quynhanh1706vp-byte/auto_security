#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_v16_${TS}"
echo "[BACKUP] $F.bak_runv1_v16_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_HEALMAP_WRAPPER_V16 ==="
END = "# === END VSP_RUN_V1_HEALMAP_WRAPPER_V16 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

block = f"""
{TAG}
# Commercial contract:
# - /healthz must be 200
# - POST /api/vsp/run_v1 must ALWAYS return JSON
# - If underlying run_v1 returns None -> return HTTP 500 JSON (not Flask TypeError)
# - Do NOT do url_map surgery (only heal _rules_by_endpoint rebuild)

try:
    import os as _os
    import json as _json
    import functools as _functools
    from collections import defaultdict as _defaultdict
    from flask import request as _request, jsonify as _jsonify
except Exception:
    _request = None
    _jsonify = None

def _vsp_heal_url_map_v16():
    try:
        um = app.url_map
        rules = list(um.iter_rules())
        new = _defaultdict(list)
        for r in rules:
            new[r.endpoint].append(r)
        um._rules_by_endpoint = new
        print("[VSP_RUNV1_V16] healed url_map._rules_by_endpoint endpoints=", len(new))
        return True
    except Exception as e:
        print("[VSP_RUNV1_V16] heal failed:", repr(e))
        return False

def _vsp_defaults_v16(j: dict) -> dict:
    j = j if isinstance(j, dict) else {{}}
    j.setdefault("mode", _os.environ.get("VSP_DEFAULT_MODE", "local"))
    j.setdefault("profile", _os.environ.get("VSP_DEFAULT_PROFILE", "FULL_EXT"))
    j.setdefault("target_type", "path")
    j.setdefault("target", _os.environ.get("VSP_DEFAULT_TARGET", "/home/test/Data/SECURITY-10-10-v4"))
    return j

def _vsp_json_v16(obj, status_code=None):
    # If obj has http_code and caller didn't force status_code -> use it
    if status_code is None and isinstance(obj, dict):
        hc = obj.get("http_code")
        if isinstance(hc, int) and 100 <= hc <= 599:
            status_code = hc
    if _jsonify is None:
        return obj
    resp = _jsonify(obj)
    if status_code is not None:
        resp.status_code = int(status_code)
    return resp

def _vsp_fix_status_from_body_v16(resp):
    # If JSON body has http_code 4xx/5xx but resp is 200 -> fix to http_code
    try:
        if getattr(resp, "mimetype", "") != "application/json":
            return resp
        sc = int(getattr(resp, "status_code", 200))
        if sc != 200:
            return resp
        obj = _json.loads(resp.get_data(as_text=True) or "")
        if isinstance(obj, dict):
            hc = obj.get("http_code")
            if isinstance(hc, int) and 400 <= hc <= 599:
                resp.status_code = hc
        return resp
    except Exception:
        return resp

def _vsp_wrap_run_v1_v16():
    if _request is None:
        return 0
    _vsp_heal_url_map_v16()

    rules = [r for r in app.url_map.iter_rules()
             if r.rule == "/api/vsp/run_v1" and "POST" in (r.methods or set())]
    if not rules:
        print("[VSP_RUNV1_V16] no POST /api/vsp/run_v1 rule found")
        return 0

    n = 0
    for r in rules:
        ep = r.endpoint
        orig = app.view_functions.get(ep)
        if not orig:
            continue

        @_functools.wraps(orig)
        def _wrapped(*args, __orig=orig, __ep=ep, **kwargs):
            try:
                j = _request.get_json(silent=True)
                j = j if isinstance(j, dict) else {{}}
                j = _vsp_defaults_v16(j)

                # Force cached json so downstream sees defaults (Flask uses dict map)
                try:
                    _request._cached_json = {{False: j, True: j}}
                except Exception:
                    pass

                out = __orig(*args, **kwargs)

                # IMPORTANT: handle None (commercial-safe)
                if out is None:
                    return _vsp_json_v16({{
                        "ok": False,
                        "error": "RUN_V1_RETURNED_NONE",
                        "http_code": 500,
                        "message": f"endpoint={{__ep}} returned None (missing return in vsp_run_api_v1.run_v1)"
                    }}, 500)

                # Tuple returns
                if isinstance(out, tuple) and len(out) >= 2:
                    body, code = out[0], out[1]
                    if isinstance(body, (dict, list)):
                        return _vsp_fix_status_from_body_v16(_vsp_json_v16(body, int(code)))
                    return out

                # Dict/list -> JSON
                if isinstance(out, (dict, list)):
                    return _vsp_fix_status_from_body_v16(_vsp_json_v16(out, None))

                # Flask Response -> try fix status if body says http_code
                return _vsp_fix_status_from_body_v16(out)

            except Exception as e:
                return _vsp_json_v16({{
                    "ok": False,
                    "error": "HTTP_500_INTERNAL",
                    "http_code": 500,
                    "message": str(e)
                }}, 500)

        app.view_functions[ep] = _wrapped
        n += 1
        print("[VSP_RUNV1_V16] wrapped endpoint=", ep, "orig=", getattr(orig, "__name__", "<?>"))
    return n

# healthz contract
try:
    has_hz = any(getattr(r, "rule", None) == "/healthz" for r in app.url_map.iter_rules())
    if not has_hz:
        @app.route("/healthz", methods=["GET"])
        def _healthz_v16():
            return _vsp_json_v16({{"ok": True, "service": "vsp-ui-8910"}}, 200)
        print("[VSP_RUNV1_V16] installed /healthz")
except Exception as _e:
    print("[VSP_RUNV1_V16] healthz install failed:", repr(_e))

try:
    _n = _vsp_wrap_run_v1_v16()
    print("[VSP_RUNV1_V16] installed wrappers:", _n)
except Exception as _e:
    print("[VSP_RUNV1_V16] install exception:", repr(_e))
{END}
"""

t = t.rstrip() + "\n\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended V16 block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# hard clean port 8910
PORT=8910
PIDS="$(ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
for pid in $PIDS; do echo "[KILL] $pid"; kill -9 "$pid" 2>/dev/null || true; done
sleep 1

systemctl --user start vsp-ui-8910.service
sleep 1

echo "== verify healthz =="
curl -sS -i http://127.0.0.1:8910/healthz | sed -n '1,80p'
echo
echo "== verify run_v1 {} =="
curl -sS -i -X POST http://127.0.0.1:8910/api/vsp/run_v1 -H 'Content-Type: application/json' -d '{}' | sed -n '1,220p'
