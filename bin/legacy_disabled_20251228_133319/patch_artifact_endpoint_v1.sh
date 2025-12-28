#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_artifact_${TS}"
echo "[BACKUP] $F.bak_artifact_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP ARTIFACT ENDPOINT V1 ==="
if MARK in txt:
    print("[OK] artifact endpoint already present")
    sys.exit(0)

block = r'''
# === VSP ARTIFACT ENDPOINT V1 ===
from flask import request, abort, send_file

def _vsp_safe_join(base: str, rel: str) -> str:
    import os
    base_abs = os.path.abspath(base)
    target = os.path.abspath(os.path.join(base_abs, rel.strip("/")))
    if not (target == base_abs or target.startswith(base_abs + os.sep)):
        raise ValueError("path traversal")
    return target

@app.get("/api/vsp/run_artifact_v1/<rid>")
def vsp_run_artifact_v1(rid):
    # expects run_status_v1(rid) returns ci_run_dir
    try:
        # reuse existing status builder if present
        st = None
        try:
            st = run_status_v1(rid)  # may return Response
        except Exception:
            st = None

        # fallback: compute ci_run_dir from your existing mapping if any
        # Here we read persisted uireq state if exists
        from pathlib import Path
        import json
        u = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1") / f"{rid}.json"
        ci_dir = None
        if u.exists():
            try:
                ci_dir = json.loads(u.read_text(encoding="utf-8")).get("ci_run_dir")
            except Exception:
                ci_dir = None

        if not ci_dir:
            abort(404, "ci_run_dir missing")

        rel = request.args.get("path", "")
        if not rel:
            abort(400, "missing path")
        full = _vsp_safe_join(ci_dir, rel)
        if not Path(full).exists():
            abort(404, "not found")
        # serve as plain text for logs/html/json; browser can download others
        return send_file(full, as_attachment=False)
    except Exception as e:
        abort(400, str(e))
# === END VSP ARTIFACT ENDPOINT V1 ===
'''

# Append near bottom
p.write_text(txt.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended artifact endpoint")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"
