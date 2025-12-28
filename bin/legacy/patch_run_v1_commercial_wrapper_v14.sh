#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_wrap_v14_${TS}"
echo "[BACKUP] $F.bak_runv1_wrap_v14_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_COMMERCIAL_WRAPPER_V14 ==="
END = "# === END VSP_RUN_V1_COMMERCIAL_WRAPPER_V14 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# (Optional) remove older tagged blocks that often cause flapping / weird status
# Only remove blocks that have proper END marker (safe).
old = re.compile(r"(?ms)\n?\s*# === VSP_RUN_V1_.*? ===.*?# === END VSP_RUN_V1_.*? ===\s*\n?")
t, n_rm = old.subn("\n", t)
print("[INFO] removed old tagged run_v1 blocks:", n_rm)

# Ensure imports exist
if not re.search(r"(?m)^\s*import\s+os\s*$", t): t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+json\s*$", t): t = "import json\n" + t
if not re.search(r"(?m)^\s*import\s+functools\s*$", t): t = "import functools\n" + t

block = f"""
{TAG}
# Commercial: do NOT mutate url_map internals.
# Wrap the *currently bound* POST /api/vsp/run_v1 endpoint by replacing app.view_functions[endpoint].
# - Accepts {{}} (defaults)
# - Forces request.get_json() to return dict via request._cached_json
# - Returns HTTP codes correctly (no more 200-with-ok=false)
try:
    import json as _json
    import os as _os
    import functools as _functools
    from flask import request as _request, jsonify as _jsonify
except Exception:
    _request = None

def _vsp_runv1_defaults_v14(payload: dict) -> dict:
    # Keep it deterministic + commercial-safe
    payload = payload if isinstance(payload, dict) else {{}}
    payload.setdefault("mode", _os.environ.get("VSP_DEFAULT_MODE", "local"))
    payload.setdefault("profile", _os.environ.get("VSP_DEFAULT_PROFILE", "FULL_EXT"))
    payload.setdefault("target_type", "path")
    payload.setdefault("target", _os.environ.get("VSP_DEFAULT_TARGET", "/home/test/Data/SECURITY-10-10-v4"))
    return payload

def _vsp_make_json_response_v14(obj, status_code: int | None = None):
    # obj can be dict/list/str
    try:
        resp = _jsonify(obj)
    except Exception:
        resp = _jsonify({{"ok": False, "error": "HTTP_500_INTERNAL", "message": "jsonify_failed", "http_code": 500}})
        status_code = 500
    if status_code is not None:
        resp.status_code = int(status_code)
    return resp

def _vsp_fix_status_from_body_v14(resp):
    # If handler returns ok=false + http_code but status is 200 => fix it
    try:
        if getattr(resp, "mimetype", "") != "application/json":
            return resp
        if getattr(resp, "status_code", 200) != 200:
            return resp
        body = resp.get_data(as_text=True) or ""
        obj = _json.loads(body)
        if isinstance(obj, dict) and obj.get("ok") is False:
            hc = obj.get("http_code")
            if isinstance(hc, int) and 400 <= hc <= 599:
                resp.status_code = hc
        return resp
    except Exception:
        return resp

def _vsp_install_run_v1_wrapper_v14():
    if _request is None:
        return 0
    n = 0
    try:
        # find all POST rules for /api/vsp/run_v1
        rules = []
        for r in app.url_map.iter_rules():
            if r.rule == "/api/vsp/run_v1" and "POST" in (r.methods or set()):
                rules.append(r)
        if not rules:
            print("[VSP_RUNV1_V14] no POST rule for /api/vsp/run_v1 found; skip")
            return 0

        for r in rules:
            ep = r.endpoint
            orig = app.view_functions.get(ep)
            if not orig:
                continue

            @_functools.wraps(orig)
            def _wrapped(*args, __orig=orig, **kwargs):
                try:
                    # parse json safely
                    j = _request.get_json(silent=True)
                    j = j if isinstance(j, dict) else {{}}
                    j = _vsp_runv1_defaults_v14(j)

                    # force cache so downstream uses defaults even if it calls request.get_json again
                    try:
                        _request._cached_json = {{False: j, True: j}}
                    except Exception:
                        pass

                    out = __orig(*args, **kwargs)

                    # If view returns tuple (body, code) or (body, code, headers)
                    if isinstance(out, tuple) and len(out) >= 2:
                        body, code = out[0], out[1]
                        if isinstance(body, (dict, list)):
                            resp = _vsp_make_json_response_v14(body, int(code))
                            return _vsp_fix_status_from_body_v14(resp)
                        return out

                    # If view returns dict/list => jsonify
                    if isinstance(out, (dict, list)):
                        resp = _vsp_make_json_response_v14(out, None)
                        return _vsp_fix_status_from_body_v14(resp)

                    # If Response-like => fix status if needed
                    return _vsp_fix_status_from_body_v14(out)
                except Exception as e:
                    return _vsp_make_json_response_v14({{
                        "ok": False,
                        "error": "HTTP_500_INTERNAL",
                        "message": str(e),
                        "http_code": 500
                    }}, 500)

            app.view_functions[ep] = _wrapped
            n += 1
            print("[VSP_RUNV1_V14] wrapped endpoint=", ep, "orig=", getattr(orig, "__name__", "<?>"))
        return n
    except Exception as e:
        print("[VSP_RUNV1_V14] install failed:", repr(e))
        return 0

# Install immediately at import-time (routes already defined by now in this monolithic file)
try:
    _n = _vsp_install_run_v1_wrapper_v14()
    print("[VSP_RUNV1_V14] installed wrappers:", _n)
except Exception as _e:
    print("[VSP_RUNV1_V14] install exception:", repr(_e))
{END}
"""

t = t.rstrip() + "\n\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended V14 commercial wrapper")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
