#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F (gunicorn is using wsgi_vsp_ui_gateway:application)"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportv3_${TS}"
echo "[BACKUP] $F.bak_exportv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Skip if already installed
if re.search(r"/api/vsp/run_export_v3/<", t) or "VSP_GATEWAY_EXPORT_V3_IN_WSGI_V1" in t:
    print("[OK] export_v3 already present in wsgi gateway, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_GATEWAY_EXPORT_V3_IN_WSGI_V1 ===
def _vsp_install_export_v3_on_app(_app):
    # Install export route on the REAL gateway Flask app (application/app)
    try:
        from flask import request, jsonify, send_file, Response
    except Exception:
        return
    from pathlib import Path
    import glob, mimetypes

    if _app is None or not hasattr(_app, "route"):
        return
    if getattr(_app, "_vsp_export_v3_installed", False):
        return
    setattr(_app, "_vsp_export_v3_installed", True)

    def _vsp_norm_rid_to_ci_key(rid: str) -> str:
        s = (rid or "").strip()
        if s.startswith("RUN_"):
            s = s[len("RUN_"):]
        return s

    def _vsp_resolve_ci_run_dir(rid: str):
        key = _vsp_norm_rid_to_ci_key(rid)
        bases = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        for b in bases:
            d = Path(b) / key
            if d.is_dir():
                return d
        # glob fallback
        pats = [f"**/{key}", f"**/RUN_{key}", f"**/{key}*"]
        for b in bases:
            bp = Path(b)
            if not bp.exists():
                continue
            for pat in pats:
                for m in bp.glob(pat):
                    if m.is_dir():
                        return m
        return None

    def _vsp_export_candidates(ci_run_dir, fmt: str):
        d = Path(ci_run_dir)
        html = [
            d / "reports" / "vsp_run_report_cio_v3.html",
            d / "reports" / "report.html",
            d / "reports" / "index.html",
            d / "vsp_run_report_cio_v3.html",
            d / "report.html",
        ]
        pdf = [
            d / "reports" / "report.pdf",
            d / "reports" / "vsp_run_report_cio_v3.pdf",
            d / "report.pdf",
        ]
        zips = [
            d / "reports" / "report.zip",
            d / "reports.zip",
            d / "report.zip",
        ]
        if fmt == "html":
            cands = html + [Path(x) for x in glob.glob(str(d / "reports" / "*.html"))]
        elif fmt == "pdf":
            cands = pdf + [Path(x) for x in glob.glob(str(d / "reports" / "*.pdf"))]
        else:
            cands = zips + [Path(x) for x in glob.glob(str(d / "reports" / "*.zip"))]

        out = []
        for f in cands:
            try:
                if f.is_file() and f.stat().st_size > 0:
                    out.append(f)
            except Exception:
                pass
        # de-dupe
        seen = set(); uniq = []
        for f in out:
            k = str(f)
            if k not in seen:
                uniq.append(f); seen.add(k)
        return uniq

    @_app.route("/api/vsp/run_export_v3/<rid>", methods=["GET","HEAD"])
    def api_vsp_run_export_v3(rid):
        fmt = (request.args.get("fmt", "html") or "html").lower().strip()
        if fmt not in ("html","pdf","zip"):
            return jsonify(ok=False, error="bad_fmt", fmt=fmt), 400

        ci_dir = _vsp_resolve_ci_run_dir(rid)
        if not ci_dir:
            return jsonify(ok=False, error="run_not_found", rid=rid), 404

        cands = _vsp_export_candidates(ci_dir, fmt)
        if not cands:
            # IMPORTANT: differentiate from missing-route
            return jsonify(ok=False, error="export_file_not_found", rid=rid, fmt=fmt, ci_run_dir=str(ci_dir)), 404

        f = cands[0]
        ctype = mimetypes.guess_type(str(f))[0] or ("text/html" if fmt=="html" else "application/pdf" if fmt=="pdf" else "application/zip")

        if request.method == "HEAD":
            resp = Response(status=200)
            resp.headers["Content-Type"] = ctype
            try:
                resp.headers["Content-Length"] = str(f.stat().st_size)
            except Exception:
                pass
            return resp

        as_attach = (fmt == "zip")
        return send_file(str(f), mimetype=ctype, as_attachment=as_attach, download_name=f.name)

# Install onto the live app
try:
    _APP = globals().get("application") or globals().get("app")
    _vsp_install_export_v3_on_app(_APP)
except Exception:
    pass
# === /VSP_GATEWAY_EXPORT_V3_IN_WSGI_V1 ===
'''

# Append at EOF (safe)
p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended export_v3 installer block to wsgi_vsp_ui_gateway.py")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"
echo "[DONE] export_v3 injected into REAL gateway module (wsgi_vsp_ui_gateway)."
