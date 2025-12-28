#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runsidx_v2_${TS}"
echo "[BACKUP] $F.bak_runsidx_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

BEG = "# === VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V1 ==="
END = "# === END VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V1 ==="
if BEG not in txt or END not in txt:
    raise SystemExit("[ERR] cannot find V1 marker block to replace")

new_block = r'''
# === VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V2 ===
from flask import jsonify, request
import os, json, re
from pathlib import Path
from datetime import datetime

def _list_files_rel(base: Path, max_files=400):
    out = []
    try:
        base = base.resolve()
        n = 0
        for root, dirs, files in os.walk(base):
            # skip heavy dirs
            dirs[:] = [d for d in dirs if d not in (".git","node_modules","dist","build","target",".venv","venv","__pycache__","cache")]
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
    files = _list_files_rel(base, max_files=1200)
    common = []
    for cand in [
        "degraded_tools.json",
        "runner.log",
        "CI_SUMMARY.txt",
        "CI_SUMMARY_HUMAN.txt",
        "kics/kics.log",
        "gitleaks/gitleaks.log",
        "semgrep/semgrep.log",
        "codeql/codeql.log",
        "report/findings_unified.json",
        "report/summary_unified.json",
    ]:
        if (base / cand).exists():
            common.append(cand)
    return jsonify({
        "ok": True,
        "rid": rid,
        "rid_norm": _norm_rid(rid),
        "ci_run_dir": ci_dir,
        "common": common,
        "files": files
    }), 200

def _parse_totals_from_summary(ci_dir: Path):
    # best-effort: read report/summary_unified.json if exists
    try:
        s = ci_dir / "report" / "summary_unified.json"
        if s.exists():
            j = json.loads(s.read_text(encoding="utf-8", errors="ignore") or "{}")
            # try common shapes
            if isinstance(j, dict):
                totals = {}
                # tolerate either summary_all/by_severity or by_severity direct
                bysev = None
                if isinstance(j.get("summary_all"), dict):
                    bysev = j["summary_all"].get("by_severity")
                if bysev is None:
                    bysev = j.get("by_severity")
                if isinstance(bysev, dict):
                    totals["by_severity"] = bysev
                return totals
    except Exception:
        pass
    return {}

def _looks_like_run_dir(name: str) -> bool:
    return bool(re.match(r"^(VSP_CI|RUN_VSP|RUN_).*20\d{6}_\d{6}", name or ""))

@app.get("/api/vsp/runs_index_v3_fs_resolved")
def vsp_runs_index_v3_fs_resolved():
    """
    FS-native resolved runs index (commercial-safe).
    - does NOT depend on any existing handler naming
    - returns items with run_id/req_id + rid_norm + ci_run_dir
    """
    limit = int(request.args.get("limit","20") or "20")
    hide_empty = request.args.get("hide_empty","0") == "1"
    # filter=1 keeps only resolvable (always true here), still keep param for compatibility
    filter_unresolved = request.args.get("filter","1") == "1"

    roots = [
        Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
    ]

    dirs = []
    for r in roots:
        try:
            if r.exists():
                for d in r.iterdir():
                    if d.is_dir() and _looks_like_run_dir(d.name):
                        dirs.append(d)
        except Exception:
            continue

    # sort newest first by mtime
    dirs.sort(key=lambda d: d.stat().st_mtime, reverse=True)

    items = []
    for d in dirs:
        if len(items) >= limit:
            break

        # normalize rid: UI currently uses RUN_* but disk uses VSP_CI_*
        dir_name = d.name
        rid_norm = dir_name.replace("RUN_", "", 1) if dir_name.startswith("RUN_") else dir_name
        rid = ("RUN_" + rid_norm) if not dir_name.startswith("RUN_") else dir_name  # keep UI-style

        # hide_empty: require summary/findings exist OR at least one known log exists
        if hide_empty:
            has_any = any((d / x).exists() for x in [
                "report/findings_unified.json",
                "report/summary_unified.json",
                "kics/kics.log",
                "gitleaks/gitleaks.log",
            ])
            if not has_any:
                continue

        created_at = datetime.fromtimestamp(d.stat().st_mtime).isoformat()
        totals = _parse_totals_from_summary(d)

        items.append({
            "run_id": rid,
            "req_id": rid,
            "request_id": rid,
            "created_at": created_at,
            "profile": "",
            "target": "",
            "totals": totals or {},
            "rid_norm": rid_norm,
            "ci_run_dir": str(d),
            "source_root": str(d.parent),
        })

    return jsonify({
        "ok": True,
        "source": "fs_resolved_v2",
        "filter_unresolved": filter_unresolved,
        "items": items
    }), 200
# === END VSP ARTIFACT INDEX + RUNS INDEX RESOLVED V2 ===
'''

# replace V1 block with V2 block
start = txt.index(BEG)
end = txt.index(END) + len(END)
txt2 = txt[:start] + new_block + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced runs_index resolved block with V2 (FS scan)")
PY

/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"
sudo systemctl restart vsp-ui-8910
sudo systemctl restart vsp-ui-8911-dev
