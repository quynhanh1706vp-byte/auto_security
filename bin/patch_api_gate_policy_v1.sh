#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatepolicy_${TS}"
echo "[BACKUP] $F.bak_gatepolicy_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# idempotent
if re.search(r"/api/vsp/gate_policy_v1/<rid>", s):
    print("[OK] gate_policy_v1 already exists, skip")
    raise SystemExit(0)

# append near end (safe, minimal coupling)
append = r'''
# === VSP COMMERCIAL: gate_policy endpoint (lightweight) ===
import os, json
from flask import jsonify

def _vsp_gate_policy_find_run_dir(rid: str):
    # Reject path traversal
    if not rid or "/" in rid or ".." in rid:
        return None

    roots = []
    env_root = os.environ.get("VSP_OUT_CI_ROOT", "").strip()
    if env_root:
        roots.append(env_root)

    # common defaults in this project
    roots += [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
    ]

    for r in roots:
        try:
            cand = os.path.join(r, rid)
            if os.path.isdir(cand):
                return cand
        except Exception:
            pass
    return None

def _vsp_gate_policy_load(run_dir: str):
    gp_path = os.path.join(run_dir, "gate_policy.json")
    gp = {}
    if os.path.isfile(gp_path):
        try:
            gp = json.load(open(gp_path, "r", encoding="utf-8"))
        except Exception:
            gp = {"_error": "gate_policy_json_parse_failed"}

    # degraded markers
    deg_dir = os.path.join(run_dir, "degraded")
    deg_items = []
    if os.path.isdir(deg_dir):
        try:
            for name in sorted(os.listdir(deg_dir)):
                fp = os.path.join(deg_dir, name)
                if os.path.isfile(fp):
                    deg_items.append(name)
        except Exception:
            pass

    verdict = gp.get("verdict") or gp.get("overall_verdict") or gp.get("status") or "UNKNOWN"
    reasons = gp.get("reasons") or gp.get("reason") or []
    if isinstance(reasons, str):
        reasons = [reasons]

    return {
        "verdict": verdict,
        "reasons": reasons,
        "degraded_n": len(deg_items),
        "degraded_items": deg_items,
        "raw": gp,
    }

@app.route("/api/vsp/gate_policy_v1/<rid>", methods=["GET"])
def api_vsp_gate_policy_v1(rid):
    run_dir = _vsp_gate_policy_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok": False, "error": "run_dir_not_found", "run_id": rid}), 404
    out = _vsp_gate_policy_load(run_dir)
    out.update({"ok": True, "run_id": rid, "ci_run_dir": run_dir})
    return jsonify(out)
'''
# insert before __main__ if exists, else append
m = re.search(r"\nif\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*\n", s)
if m:
    s2 = s[:m.start()] + "\n" + append + "\n" + s[m.start():]
else:
    s2 = s.rstrip() + "\n\n" + append + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] appended gate_policy_v1 endpoint")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn (your usual restart script)"
