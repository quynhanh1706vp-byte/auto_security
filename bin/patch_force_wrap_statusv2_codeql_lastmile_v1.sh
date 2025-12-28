#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_forcewrap_v2_${TS}"
echo "[BACKUP] $F.bak_forcewrap_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FORCE_WRAP_STATUSV2_CODEQL_LASTMILE_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_FORCE_WRAP_STATUSV2_CODEQL_LASTMILE_V1 ===
def _vsp__inject_codeql_fields(data: dict):
    import os, json
    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or data.get("ci_dir") or ""
    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    # force keys exist (never null)
    data["has_codeql"] = bool(data.get("has_codeql") or False)
    data["codeql_verdict"] = data.get("codeql_verdict") or None
    try:
        data["codeql_total"] = int(data.get("codeql_total") or 0)
    except Exception:
        data["codeql_total"] = 0

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
    return data

def _vsp__force_wrap_status_v2_endpoint():
    # Unconditional re-wrap status_v2 endpoint so our injector runs LAST.
    try:
        from functools import wraps
        from flask import jsonify
        for r in list(app.url_map.iter_rules()):
            if "/api/vsp/run_status_v2" in (r.rule or ""):
                ep = r.endpoint
                orig = app.view_functions.get(ep)
                if not orig:
                    continue

                @wraps(orig)
                def wrapped(*a, __orig=orig, **kw):
                    ret = __orig(*a, **kw)

                    # Get dict from Response/dict
                    data = None
                    try:
                        if hasattr(ret, "get_json"):
                            data = ret.get_json(silent=True)
                        elif isinstance(ret, dict):
                            data = ret
                    except Exception:
                        data = None

                    if not isinstance(data, dict):
                        return ret

                    data = _vsp__inject_codeql_fields(data)
                    return jsonify(data)

                app.view_functions[ep] = wrapped
                try:
                    print("[VSP_FORCE_WRAP_V2] wrapped", ep, r.rule)
                except Exception:
                    pass
    except Exception as e:
        try:
            print("[VSP_FORCE_WRAP_V2][WARN]", e)
        except Exception:
            pass

try:
    _vsp__force_wrap_status_v2_endpoint()
except Exception:
    pass
'''
p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended force-wrap v2 last-mile")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== VERIFY =="
CI="/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251215_034956"
RID="RUN_$(basename "$CI")"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict}'
