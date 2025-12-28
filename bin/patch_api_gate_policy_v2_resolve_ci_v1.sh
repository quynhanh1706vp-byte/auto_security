#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatepolicyv2_${TS}"
echo "[BACKUP] $F.bak_gatepolicyv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "/api/vsp/gate_policy_v2/<rid>" in s:
    print("[OK] gate_policy_v2 already exists, skip")
    raise SystemExit(0)

append = r'''
# === VSP COMMERCIAL: gate_policy_v2 (resolve ci_run_dir via uireq mapping / run_status_v2) ===
import glob
from flask import jsonify

def _vsp_try_resolve_run_dir_from_uireq(rid: str):
    # uireq_v1 persist location (per your commercial design)
    cand_dirs = [
        "out_ci/uireq_v1",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1_state",
    ]
    names = [
        f"{rid}.json",
        f"{rid}_state.json",
        f"{rid}.state.json",
    ]
    for d in cand_dirs:
        try:
            for nm in names:
                fp = os.path.join(d, nm)
                if os.path.isfile(fp):
                    try:
                        j = json.load(open(fp, "r", encoding="utf-8"))
                    except Exception:
                        continue
                    run_dir = j.get("ci_run_dir") or j.get("ci") or j.get("run_dir") or j.get("RUN_DIR")
                    if run_dir and os.path.isdir(str(run_dir)):
                        return str(run_dir)
        except Exception:
            pass

    # last fallback: glob (bounded)
    for d in cand_dirs:
        try:
            if not os.path.isdir(d):
                continue
            pats = [
                os.path.join(d, f"{rid}*.json"),
                os.path.join(d, f"*{rid}*.json"),
            ]
            hits = []
            for pat in pats:
                hits += glob.glob(pat)[:20]
            for fp in hits[:20]:
                try:
                    j = json.load(open(fp, "r", encoding="utf-8"))
                except Exception:
                    continue
                run_dir = j.get("ci_run_dir") or j.get("ci") or j.get("run_dir") or j.get("RUN_DIR")
                if run_dir and os.path.isdir(str(run_dir)):
                    return str(run_dir)
        except Exception:
            pass
    return None

def _vsp_try_resolve_run_dir_from_statusv2_http(rid: str):
    # safest fallback; ok in gunicorn multi-worker. If single worker, still usually fine.
    try:
        import urllib.request
        url = f"http://127.0.0.1:8910/api/vsp/run_status_v2/{rid}"
        with urllib.request.urlopen(url, timeout=2.5) as r:
            raw = r.read().decode("utf-8", "ignore")
        j = json.loads(raw)
        run_dir = j.get("ci_run_dir") or j.get("ci") or j.get("run_dir")
        if run_dir and os.path.isdir(str(run_dir)):
            return str(run_dir)
    except Exception:
        return None
    return None

@app.route("/api/vsp/gate_policy_v2/<rid>", methods=["GET"])
def api_vsp_gate_policy_v2(rid):
    # Reject traversal
    if not rid or "/" in rid or ".." in rid:
        return jsonify({"ok": False, "error": "bad_rid", "run_id": rid}), 400

    # 1) try mapping uireq
    run_dir = _vsp_try_resolve_run_dir_from_uireq(rid)

    # 2) try old heuristic (folder name)
    if not run_dir:
        run_dir = _vsp_gate_policy_find_run_dir(rid)

    # 3) fallback via run_status_v2
    if not run_dir:
        run_dir = _vsp_try_resolve_run_dir_from_statusv2_http(rid)

    if not run_dir:
        return jsonify({"ok": False, "error": "run_dir_not_found", "run_id": rid}), 404

    out = _vsp_gate_policy_load(run_dir)
    out.update({"ok": True, "run_id": rid, "ci_run_dir": run_dir, "_resolver": "v2"})
    return jsonify(out)
'''

# insert near end
s2 = s.rstrip() + "\n\n" + append + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended gate_policy_v2 endpoint")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
