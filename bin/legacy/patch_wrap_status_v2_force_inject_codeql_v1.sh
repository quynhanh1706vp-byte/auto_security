#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_codeql_${TS}"
echo "[BACKUP] $F.bak_force_codeql_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FORCE_CODEQL_IN_STATUSV2_WRAPPER_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# We replace the existing _vsp__postprocess_status_v2 with a stronger version if exists,
# else append a stronger function and re-install wrappers.
if "_vsp__postprocess_status_v2" in t:
    # inject a strong override by redefining later in file (Python takes last definition)
    pass

block = r'''
# === VSP_FORCE_CODEQL_IN_STATUSV2_WRAPPER_V1 ===
def _vsp__postprocess_status_v2(ret):
    import os, json
    # ALWAYS convert to dict if possible
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

    # resolve ci dir from multiple possible keys
    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or data.get("ci_dir") or ""
    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    # inject defaults (force keys exist)
    data["has_codeql"] = bool(data.get("has_codeql", False))
    data["codeql_verdict"] = data.get("codeql_verdict", None)
    data["codeql_total"] = int(data.get("codeql_total") or 0) if str(data.get("codeql_total") or "0").isdigit() else 0

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
                    data["codeql_total"] = data.get("codeql_total") or 0
    except Exception:
        pass

    # CRITICAL: always jsonify so wrapper output wins
    try:
        from flask import jsonify
        return jsonify(data)
    except Exception:
        return data
'''
t2 = t + "\n\n" + block + "\n"
p.write_text(t2, encoding="utf-8")
print("[OK] appended strong _vsp__postprocess_status_v2 override")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] missing restart script; restart 8910 manually"
fi

echo "== VERIFY =="
CI="/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251215_034956"
RID="RUN_$(basename "$CI")"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict}'
