#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_v15_${TS}"
echo "[BACKUP] $F.bak_runv1_v15_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_HEALMAP_WRAPPER_V15 ==="
END = "# === END VSP_RUN_V1_HEALMAP_WRAPPER_V15 ==="

if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure imports exist (safe prepend)
need = []
if not re.search(r"(?m)^\s*import\s+os\s*$", t): need.append("import os\n")
if not re.search(r"(?m)^\s*import\s+json\s*$", t): need.append("import json\n")
if not re.search(r"(?m)^\s*import\s+functools\s*$", t): need.append("import functools\n")
if not re.search(r"(?m)^\s*from\s+collections\s+import\s+defaultdict\s*$", t): need.append("from collections import defaultdict\n")
if need:
    t = "".join(need) + t

block = f"""
{TAG}
# Commercial: DO NOT touch url_map._rules list.
# 1) Heal url_map._rules_by_endpoint (fix KeyError in Werkzeug redirect/match)
# 2) Wrap the bound POST /api/vsp/run_v1 endpoint via app.view_functions (no url_map surgery)
try:
    import os as _os
    import json as _json
    import functools as _functools
    from collections import defaultdict as _defaultdict
    from flask import request as _request, jsonify as _jsonify
except Exception:
    _request = None

def _vsp_heal_url_map_v15():
    try:
        um = app.url_map
        rules = list(um.iter_rules())
        new = _defaultdict(list)
        for r in rules:
            new[r.endpoint].append(r)
        um._rules_by_endpoint = new
        print("[VSP_RUNV1_V15] healed url_map._rules_by_endpoint endpoints=", len(new))
        return True
    except Exception as e:
        print("[VSP_RUNV1_V15] heal failed:", repr(e))
        return False

def _vsp_defaults_v15(j: dict) -> dict:
    j = j if isinstance(j, dict) else {{}}
    j.setdefault("mode", _os.environ.get("VSP_DEFAULT_MODE", "local"))
    j.setdefault("profile", _os.environ.get("VSP_DEFAULT_PROFILE", "FULL_EXT"))
    j.setdefault("target_type", "path")
    j.setdefault("target", _os.environ.get("VSP_DEFAULT_TARGET", "/home/test/Data/SECURITY-10-10-v4"))
    return j

def _vsp_json_v15(obj, status_code=None):
    try:
        resp = _jsonify(obj)
    except Exception:
        resp = _jsonify({{"ok": False, "error": "HTTP_500_INTERNAL", "http_code": 500, "message": "jsonify_failed"}})
        status_code = 500
    if status_code is not None:
        resp.status_code = int(status_code)
    return resp

def _vsp_fix_status_v15(resp):
    try:
        if getattr(resp, "mimetype", "") != "application/json":
            return resp
        if getattr(resp, "status_code", 200) != 200:
            return resp
        obj = _json.loads(resp.get_data(as_text=True) or "")
        if isinstance(obj, dict) and obj.get("ok") is False:
            hc = obj.get("http_code")
            if isinstance(hc, int) and 400 <= hc <= 599:
                resp.status_code = hc
        return resp
    except Exception:
        return resp

def _vsp_wrap_run_v1_v15():
    if _request is None:
        return 0
    n = 0
    # Heal first to avoid KeyError in request matching
    _vsp_heal_url_map_v15()

    rules = [r for r in app.url_map.iter_rules()
             if r.rule == "/api/vsp/run_v1" and "POST" in (r.methods or set())]
    if not rules:
        print("[VSP_RUNV1_V15] no POST /api/vsp/run_v1 rule found")
        return 0

    for r in rules:
        ep = r.endpoint
        orig = app.view_functions.get(ep)
        if not orig:
            continue

        @_functools.wraps(orig)
        def _wrapped(*args, __orig=orig, **kwargs):
            try:
                j = _request.get_json(silent=True)
                j = j if isinstance(j, dict) else {{}}
                j = _vsp_defaults_v15(j)

                # force cached json so downstream sees defaults
                try:
                    _request._cached_json = {{False: j, True: j}}
                except Exception:
                    pass

                out = __orig(*args, **kwargs)

                # tuple returns
                if isinstance(out, tuple) and len(out) >= 2:
                    body, code = out[0], out[1]
                    if isinstance(body, (dict, list)):
                        return _vsp_fix_status_v15(_vsp_json_v15(body, int(code)))
                    return out

                if isinstance(out, (dict, list)):
                    return _vsp_fix_status_v15(_vsp_json_v15(out, None))

                return _vsp_fix_status_v15(out)
            except Exception as e:
                return _vsp_json_v15({{
                    "ok": False,
                    "error": "HTTP_500_INTERNAL",
                    "http_code": 500,
                    "message": str(e)
                }}, 500)

        app.view_functions[ep] = _wrapped
        n += 1
        print("[VSP_RUNV1_V15] wrapped endpoint=", ep, "orig=", getattr(orig, "__name__", "<?>"))
    return n

try:
    _n = _vsp_wrap_run_v1_v15()
    print("[VSP_RUNV1_V15] installed wrappers:", _n)
except Exception as _e:
    print("[VSP_RUNV1_V15] install exception:", repr(_e))
{END}
"""

t = t.rstrip() + "\n\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended V15 heal+wrapper block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# hard clean port 8910 (commercial stable)
PORT=8910
PIDS="$(ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
for pid in $PIDS; do echo "[KILL] $pid"; kill -9 "$pid" 2>/dev/null || true; done
sleep 1

systemctl --user start vsp-ui-8910.service
sleep 1

echo "== verify =="
curl -sS http://127.0.0.1:8910/healthz; echo
curl -sS -i -X POST http://127.0.0.1:8910/api/vsp/run_v1 -H 'Content-Type: application/json' -d '{}' | sed -n '1,160p'
