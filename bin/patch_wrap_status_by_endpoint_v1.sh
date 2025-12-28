#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrap_endpoint_${TS}"
echo "[BACKUP] $F.bak_wrap_endpoint_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WRAP_STATUS_BY_ENDPOINT_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Append helper + installer at end of file (robust, no regex on return)
block = r'''
# === VSP_WRAP_STATUS_BY_ENDPOINT_V1 ===
def _vsp__safe_json_from_response(ret):
    try:
        if hasattr(ret, "get_json"):
            data = ret.get_json(silent=True)
            if isinstance(data, dict):
                return data, True
    except Exception:
        pass
    if isinstance(ret, dict):
        return ret, False
    return None, False

def _vsp__pick_latest_ci_dir():
    import glob, os
    pats = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_*",
        "/home/test/Data/*/out_ci/VSP_CI_*",
    ]
    cands = []
    for pat in pats:
        cands.extend(glob.glob(pat))
    cands = [c for c in cands if os.path.isdir(c)]
    cands.sort(reverse=True)
    return cands[0] if cands else ""

def _vsp__postprocess_status_v1(ret):
    import datetime, os, json
    from flask import request
    data, is_resp = _vsp__safe_json_from_response(ret)
    if not isinstance(data, dict):
        return ret

    # normalize empties
    data["stage_name"] = data.get("stage_name") or ""
    data["ci_run_dir"] = data.get("ci_run_dir") or ""
    if data.get("pct", None) is None:
        data["pct"] = None

    rid = ""
    try:
        rid = (request.path or "").rstrip("/").split("/")[-1]
    except Exception:
        rid = ""

    # resolve ci_run_dir if empty: fallback newest CI dir
    if not data["ci_run_dir"]:
        data["ci_run_dir"] = _vsp__pick_latest_ci_dir()

    # persist uireq state (commercial)
    try:
        base = os.path.join(os.path.dirname(__file__), "out_ci", "uireq_v1")
        os.makedirs(base, exist_ok=True)
        if rid:
            sp = os.path.join(base, f"{rid}.json")
            payload = dict(data)
            payload["req_id"] = rid
            payload["ts_persist"] = datetime.datetime.utcnow().isoformat() + "Z"
            open(sp, "w", encoding="utf-8").write(json.dumps(payload, ensure_ascii=False, indent=2))
    except Exception:
        pass

    if is_resp:
        try:
            from flask import jsonify
            return jsonify(data)
        except Exception:
            return ret
    return data

def _vsp__postprocess_status_v2(ret):
    import os, json
    data, is_resp = _vsp__safe_json_from_response(ret)
    if not isinstance(data, dict):
        return ret

    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or ""
    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    data.setdefault("has_codeql", False)
    data.setdefault("codeql_verdict", None)
    data.setdefault("codeql_total", 0)

    try:
        if codeql_dir and os.path.isdir(codeql_dir):
            if os.path.isfile(summary):
                try:
                    j = json.load(open(summary, "r", encoding="utf-8"))
                except Exception:
                    j = {}
                data["has_codeql"] = True
                data["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict") or "AMBER"
                try:
                    data["codeql_total"] = int(j.get("total") or 0)
                except Exception:
                    data["codeql_total"] = 0
            else:
                sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
                if sarifs:
                    data["has_codeql"] = True
                    data["codeql_verdict"] = data.get("codeql_verdict") or "AMBER"
    except Exception:
        pass

    if is_resp:
        try:
            from flask import jsonify
            return jsonify(data)
        except Exception:
            return ret
    return data

def _vsp__install_status_wrappers(app):
    # Wrap actual endpoints by URL rule contains substr (no parsing return statement)
    try:
        from functools import wraps
        def wrap_rule(substr, post_fn):
            for r in list(app.url_map.iter_rules()):
                if substr in (r.rule or ""):
                    ep = r.endpoint
                    orig = app.view_functions.get(ep)
                    if not orig or getattr(orig, "_vsp_wrapped", False):
                        continue
                    @wraps(orig)
                    def wrapped(*a, __orig=orig, __post=post_fn, **kw):
                        ret = __orig(*a, **kw)
                        return __post(ret)
                    wrapped._vsp_wrapped = True
                    app.view_functions[ep] = wrapped
                    try:
                        print("[VSP_WRAP] wrapped", ep, r.rule)
                    except Exception:
                        pass
        wrap_rule("/api/vsp/run_status_v1", _vsp__postprocess_status_v1)
        wrap_rule("/api/vsp/run_status_v2", _vsp__postprocess_status_v2)
    except Exception as e:
        try:
            print("[VSP_WRAP][WARN]", e)
        except Exception:
            pass

try:
    # app object exists in module scope
    _vsp__install_status_wrappers(app)
except Exception:
    pass
'''

t2 = t + ("\n\n" + block + "\n")
p.write_text(t2, encoding="utf-8")
print("[OK] appended endpoint wrapper block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
