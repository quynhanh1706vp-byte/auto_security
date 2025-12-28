#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_artopen_${TS}"
echo "[BACKUP] $F.bak_artopen_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG="VSP_GATEWAY_ARTIFACT_OPEN_V1"
if TAG in t or "/api/vsp/run_artifact_open_v1/" in t:
    print("[OK] artifact_open already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_GATEWAY_ARTIFACT_OPEN_V1 ===
def _vsp_install_artifact_open_v1(_app):
    try:
        from flask import request, jsonify, send_file
    except Exception:
        return
    from pathlib import Path
    import mimetypes

    if _app is None or not hasattr(_app, "route"):
        return
    if getattr(_app, "_vsp_artifact_open_v1_installed", False):
        return
    setattr(_app, "_vsp_artifact_open_v1_installed", True)

    # reuse resolver from export_v3 if present
    _resolve = globals().get("_vsp_resolve_ci_run_dir", None)
    if _resolve is None:
        def _resolve(rid: str):
            key = (rid or "").strip()
            if key.startswith("RUN_"):
                key = key[len("RUN_"):]
            bases = [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            ]
            for b in bases:
                d = Path(b) / key
                if d.is_dir():
                    return d
            return None

    # simple whitelist for rel paths (only allow inside run dir, deny parent traversal)
    def _safe_join(run_dir: Path, rel: str):
        rel = (rel or "").lstrip("/").strip()
        if not rel:
            return None
        if ".." in rel.split("/"):
            return None
        # allow only certain top-level folders/files
        allow_prefixes = ("reports/", "findings_", "summary_", "gitleaks/", "semgrep/", "trivy/", "kics/", "codeql/", "bandit/", "syft/", "grype/", "artifacts/")
        if not (rel.startswith(allow_prefixes) or rel in ("runner.log","SUMMARY.txt")):
            return None
        f = (run_dir / rel).resolve()
        if run_dir.resolve() not in f.parents and f != run_dir.resolve():
            return None
        return f

    @_app.route("/api/vsp/run_artifact_open_v1/<rid>", methods=["GET","HEAD"])
    def api_vsp_run_artifact_open_v1(rid):
        from flask import Response
        rel = request.args.get("rel","")
        run_dir = _resolve(rid)
        if not run_dir:
            return jsonify(ok=False, error="run_not_found", rid=rid), 404

        f = _safe_join(Path(run_dir), rel)
        if not f:
            return jsonify(ok=False, error="bad_rel", rel=rel), 400
        if not f.is_file():
            return jsonify(ok=False, error="file_not_found", rel=rel), 404

        ctype = mimetypes.guess_type(str(f))[0] or "application/octet-stream"
        if request.method == "HEAD":
            resp = Response(status=200)
            resp.headers["Content-Type"] = ctype
            try:
                resp.headers["Content-Length"] = str(f.stat().st_size)
            except Exception:
                pass
            return resp

        # inline for html/json/txt; attachment for others
        as_attach = not (ctype.startswith("text/") or ctype.endswith("json") or "html" in ctype)
        return send_file(str(f), mimetype=ctype, as_attachment=as_attach, download_name=f.name)
# === /VSP_GATEWAY_ARTIFACT_OPEN_V1 ===

try:
    _APP = globals().get("application") or globals().get("app")
    _vsp_install_artifact_open_v1(_APP)
except Exception:
    pass
'''

p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended artifact_open_v1 route installer")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"
echo "[DONE] installed /api/vsp/run_artifact_open_v1/<rid>?rel=..."
