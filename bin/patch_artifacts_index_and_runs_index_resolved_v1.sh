#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_idx_${TS}"
echo "[BACKUP] $F.bak_idx_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V1 ==="
if MARK in txt:
    print("[OK] already patched")
    sys.exit(0)

block = r'''
# === VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V1 ===
from flask import jsonify, request
import os
from pathlib import Path

def _list_files_rel(base: Path, max_files=400):
    out = []
    try:
        base = base.resolve()
        n = 0
        for root, dirs, files in os.walk(base):
            # skip heavy dirs
            dirs[:] = [d for d in dirs if d not in (".git","node_modules","dist","build","target",".venv","venv","__pycache__","cache","out","out_ci")]
            for fn in files:
                n += 1
                if n > max_files:
                    return out
                fp = Path(root) / fn
                try:
                    rel = fp.resolve().relative_to(base).as_posix()
                    out.append(rel)
                except Exception:
                    pass
    except Exception:
        pass
    return out

@app.get("/api/vsp/run_artifacts_index_v1/<rid>")
def vsp_run_artifacts_index_v1(rid):
    ci_dir = _find_ci_run_dir_any(rid)  # from STATUS+ARTIFACT V2 block
    if not ci_dir:
        return jsonify({"ok": False, "rid": rid, "error": "ci_run_dir_not_found"}), 404
    base = Path(ci_dir)
    files = _list_files_rel(base, max_files=800)
    # helpful shortcuts
    common = []
    for cand in ["degraded_tools.json","runner.log","CI_SUMMARY.txt","CI_SUMMARY_HUMAN.txt",
                 "kics/kics.log","gitleaks/gitleaks.log","semgrep/semgrep.log","codeql/codeql.log",
                 "report/findings_unified.json","report/summary_unified.json"]:
        if (base / cand).exists():
            common.append(cand)
    return jsonify({"ok": True, "rid": rid, "rid_norm": _norm_rid(rid), "ci_run_dir": ci_dir, "common": common, "files": files}), 200

@app.get("/api/vsp/runs_index_v3_fs_resolved")
def vsp_runs_index_v3_fs_resolved():
    """
    Wrapper over existing /api/vsp/runs_index_v3_fs:
      - adds rid_norm + ci_run_dir when resolvable
      - optionally filters unresolved runs (filter=1 default)
    """
    limit = int(request.args.get("limit","20") or "20")
    hide_empty = request.args.get("hide_empty","0")
    filter_unresolved = request.args.get("filter","1") == "1"

    # call existing handler via HTTP-internal? easiest: reuse function if present in module scope
    try:
        # if there's a function already bound to this endpoint name in app.view_functions:
        vf = app.view_functions.get("vsp_runs_index_v3_fs") or app.view_functions.get("runs_index_v3_fs")  # best-effort
    except Exception:
        vf = None

    if not vf:
        return jsonify({"ok": False, "error": "runs_index_v3_fs_handler_not_found"}), 500

    resp = vf()
    payload = resp[0].get_json(silent=True) if isinstance(resp, tuple) else resp.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"ok": False, "error": "bad_runs_index_payload"}), 500

    items = payload.get("items") or []
    out_items = []
    for it in items[:limit]:
        rid = it.get("req_id") or it.get("request_id") or it.get("run_id")
        ci_dir = _find_ci_run_dir_any(rid) if rid else None
        if filter_unresolved and not ci_dir:
            continue
        it2 = dict(it)
        it2["rid_norm"] = _norm_rid(rid) if rid else None
        it2["ci_run_dir"] = ci_dir
        out_items.append(it2)

    payload2 = dict(payload)
    payload2["items"] = out_items
    payload2["filter_unresolved"] = filter_unresolved
    return jsonify(payload2), 200
# === END VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V1 ===
'''

p.write_text(txt.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended artifacts index + runs index resolved")
PY

/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"
sudo systemctl restart vsp-ui-8910
sudo systemctl restart vsp-ui-8911-dev
