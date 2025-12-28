#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_artifacts_api_${TS}" && echo "[BACKUP] $APP.bak_artifacts_api_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="### VSP_ARTIFACTS_API_V1 ###"
if MARK in s:
    print("[SKIP] artifacts api already present")
    raise SystemExit(0)

# inject near end (before __main__ if exists)
m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
inject_at = m.start() if m else len(s)

block = f"""
\n{MARK}
# Artifacts API: list + serve selected artifacts (commercial safe whitelist)
import os, glob
from flask import jsonify, request
try:
    from flask import send_file, abort
except Exception:
    send_file = None
    abort = None

def _vsp_resolve_run_dir_by_rid(rid: str):
    if not rid:
        return None
    pats = [
      f"/home/test/Data/*/out_ci/{{rid}}",
      f"/home/test/Data/*/out/{{rid}}",
      f"/home/test/Data/SECURITY-10-10-v4/out_ci/{{rid}}",
      f"/home/test/Data/SECURITY_BUNDLE/out_ci/{{rid}}",
    ]
    for pat in pats:
        for d in glob.glob(pat.format(rid=rid)):
            if os.path.isdir(d):
                return d
    return None

# whitelist relative paths we are allowed to expose
_VSP_ART_WHITELIST = [
  "kics/kics.log",
  "kics/kics.json",
  "kics/kics_summary.json",
  "codeql/codeql.log",
  "codeql/codeql.sarif",
  "trivy/trivy.json",
  "trivy/trivy.json.err",
  "semgrep/semgrep.json",
  "gitleaks/gitleaks.json",
  "bandit/bandit.json",
  "syft/syft.json",
  "grype/grype.json",
  "SUMMARY.txt",
  "findings_unified.json",
  "findings_effective.json",
]

@app.get("/api/vsp/run_artifacts_index_v1/<rid>")
def api_vsp_run_artifacts_index_v1(rid):
    rd = _vsp_resolve_run_dir_by_rid(rid)
    if not rd:
        return jsonify({{"ok": False, "rid": rid, "error": "run_dir_not_found", "items": []}}), 200
    items = []
    for rel in _VSP_ART_WHITELIST:
        ap = os.path.join(rd, rel)
        if os.path.isfile(ap):
            try:
                sz = os.path.getsize(ap)
            except Exception:
                sz = None
            items.append({{
              "name": rel,
              "rel": rel,
              "size": sz,
              "url": f"/api/vsp/run_artifact_raw_v1/{{rid}}?rel=" + rel
            }})
    return jsonify({{"ok": True, "rid": rid, "run_dir": rd, "items": items, "items_n": len(items)}}), 200

@app.get("/api/vsp/run_artifact_raw_v1/<rid>")
def api_vsp_run_artifact_raw_v1(rid):
    if send_file is None:
        return jsonify({{"ok": False, "rid": rid, "error": "send_file_unavailable"}}), 500
    rel = request.args.get("rel","")
    if rel not in _VSP_ART_WHITELIST:
        return jsonify({{"ok": False, "rid": rid, "error": "rel_not_allowed", "rel": rel}}), 403
    rd = _vsp_resolve_run_dir_by_rid(rid)
    if not rd:
        return jsonify({{"ok": False, "rid": rid, "error": "run_dir_not_found"}}), 404
    ap = os.path.join(rd, rel)
    if not os.path.isfile(ap):
        return jsonify({{"ok": False, "rid": rid, "error": "file_not_found", "rel": rel}}), 404
    # serve inline (browser can open .log/.json)
    return send_file(ap, as_attachment=False)
"""
s2 = s[:inject_at] + block + "\n" + s[inject_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected artifacts api block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_artifacts_api_v1"
