#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_forcewrap_v2b_${TS}"
echo "[BACKUP] $F.bak_forcewrap_v2b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FORCE_WRAP_STATUSV2_CODEQL_LASTMILE_V2 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_FORCE_WRAP_STATUSV2_CODEQL_LASTMILE_V2 ===
def _vsp__parse_json_any(ret):
    import json
    # 1) normal get_json
    try:
        if hasattr(ret, "get_json"):
            d = ret.get_json(silent=True)
            if isinstance(d, dict):
                return d
    except Exception:
        pass
    # 2) dict direct
    if isinstance(ret, dict):
        return ret
    # 3) parse bytes/text body even if content-type not json
    try:
        if hasattr(ret, "get_data"):
            s = ret.get_data(as_text=True)
            if isinstance(s, str) and s.strip().startswith("{"):
                d = json.loads(s)
                if isinstance(d, dict):
                    return d
    except Exception:
        pass
    return None

def _vsp__resolve_ci_dir_from_rid(rid: str):
    import glob, os
    rid2 = (rid or "").strip()
    if rid2.startswith("RUN_"):
        rid2 = rid2[4:]
    if not rid2:
        return ""
    pats = [
        f"/home/test/Data/SECURITY-10-10-v4/out_ci/{rid2}",
        f"/home/test/Data/SECURITY-10-10-v4/out_ci/{rid2}*",
        f"/home/test/Data/*/out_ci/{rid2}",
        f"/home/test/Data/*/out_ci/{rid2}*",
        f"/home/test/Data/*/out_ci/*{rid2}*",
    ]
    cands = []
    for pat in pats:
        cands.extend(glob.glob(pat))
    cands = [c for c in cands if os.path.isdir(c)]
    cands.sort(reverse=True)
    return cands[0] if cands else ""

def _vsp__inject_codeql(data: dict, rid: str):
    import os, json
    # ensure keys never null
    data["has_codeql"] = False
    data["codeql_verdict"] = "NOT_RUN"
    data["codeql_total"] = 0

    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or data.get("ci_dir") or ""
    if not ci:
        # try rid_norm if present
        rn = data.get("rid_norm") or ""
        if rn:
            ci = _vsp__resolve_ci_dir_from_rid(rn)
    if not ci:
        ci = _vsp__resolve_ci_dir_from_rid(rid)

    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    try:
        if codeql_dir and os.path.isdir(codeql_dir):
            # treat as at least ran/exists
            data["has_codeql"] = True
            data["codeql_verdict"] = "AMBER"
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
    return data

def _vsp__force_wrap_status_v2_endpoint_v2():
    try:
        from functools import wraps
        from flask import jsonify, request
        for r in list(app.url_map.iter_rules()):
            if "/api/vsp/run_status_v2" in (r.rule or ""):
                ep = r.endpoint
                orig = app.view_functions.get(ep)
                if not orig:
                    continue

                @wraps(orig)
                def wrapped(*a, __orig=orig, **kw):
                    ret = __orig(*a, **kw)
                    data = _vsp__parse_json_any(ret)
                    if not isinstance(data, dict):
                        return ret
                    rid = ""
                    try:
                        rid = (request.path or "").rstrip("/").split("/")[-1]
                    except Exception:
                        rid = ""
                    data = _vsp__inject_codeql(data, rid)
                    return jsonify(data)

                app.view_functions[ep] = wrapped
                try:
                    print("[VSP_FORCE_WRAP_V2B] wrapped", ep, r.rule)
                except Exception:
                    pass
    except Exception as e:
        try:
            print("[VSP_FORCE_WRAP_V2B][WARN]", e)
        except Exception:
            pass

try:
    _vsp__force_wrap_status_v2_endpoint_v2()
except Exception:
    pass
'''
p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended force-wrap v2b (parse bytes + rid->ci mapping)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== VERIFY =="
CI="/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251215_034956"
RID="RUN_$(basename "$CI")"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict}'
