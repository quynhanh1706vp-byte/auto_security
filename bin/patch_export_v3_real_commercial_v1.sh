#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

# idempotent
if grep -q "VSP_EXPORT_V3_COMMERCIAL_REAL_V1" "$F"; then
  echo "[OK] export v3 commercial block already present, skip"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_v3_real_${TS}"
echo "[BACKUP] $F.bak_export_v3_real_${TS}"

cat >> "$F" <<'PY'

# === VSP_EXPORT_V3_COMMERCIAL_REAL_V1 BEGIN ===
# 목적: /api/vsp/run_export_v3/<rid> must return REAL html/zip/pdf (not JSON fallback)
try:
    from flask import request, jsonify, make_response, send_file, render_template
except Exception:
    request = None
    jsonify = None
    make_response = None
    send_file = None
    render_template = None

import os, json, tempfile, zipfile, shutil, subprocess
from pathlib import Path
from datetime import datetime, timezone

def _vsp_export_v3_resolve_run_dir_real_v1(rid: str):
    """
    Accepts:
      - RUN_VSP_CI_YYYYmmdd_HHMMSS  -> maps to VSP_CI_YYYYmmdd_HHMMSS
      - VSP_CI_YYYYmmdd_HHMMSS      -> direct
    Tries common parents to avoid slow rglob.
    """
    if not rid or rid == "null":
        return None, "rid_null"

    base = rid.strip()
    if base.startswith("RUN_"):
        base = base[len("RUN_"):]
    # now base usually == VSP_CI_...

    parents = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
    ]
    for parent in parents:
        p = Path(parent)
        if not p.exists():
            continue
        cand = p / base
        if cand.exists() and cand.is_dir():
            return str(cand), f"direct:{cand}"

    # last-resort bounded search (still cheap): check two well-known roots
    roots = ["/home/test/Data/SECURITY_BUNDLE", "/home/test/Data/SECURITY-10-10-v4"]
    for root in roots:
        r = Path(root)
        if not r.exists():
            continue
        for sub in (r / "out_ci" / base, r / "out" / base):
            if sub.exists() and sub.is_dir():
                return str(sub), f"glob:{sub}"

    return None, "not_found"

def _vsp_export_v3_pick_html_real_v1(run_dir: str):
    """
    Prefer an existing CIO html in report/.
    Otherwise generate a minimal HTML from findings_unified.json.
    """
    report = Path(run_dir) / "report"
    for name in [
        "vsp_run_report_cio_v3.html",
        "vsp_run_report_cio_v2.html",
        "run_report.html",
        "export_v3.html",
        "index.html",
        "report.html",
    ]:
        f = report / name
        if f.exists() and f.is_file() and f.stat().st_size > 200:
            return f, f"file:{name}"

    fu = Path(run_dir) / "findings_unified.json"
    total = None
    bysev = {}
    if fu.exists() and fu.is_file():
        try:
            data = json.load(open(fu, "r", encoding="utf-8"))
            total = data.get("total")
            # fast-ish severity count (cap to avoid worst-case memory)
            for it in (data.get("items") or [])[:200000]:
                sev = (it.get("severity") or "TRACE").upper()
                bysev[sev] = bysev.get(sev, 0) + 1
        except Exception:
            pass

    now = datetime.now(timezone.utc).isoformat()
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>VSP Export {run_dir}</title></head>
<body style="font-family: Arial, sans-serif">
<h1>VSP Export (Generated)</h1>
<p><b>run_dir</b>: {run_dir}</p>
<p><b>generated_at_utc</b>: {now}</p>
<h2>Findings summary</h2>
<p><b>total</b>: {total}</p>
<pre>{json.dumps(bysev, indent=2, ensure_ascii=False)}</pre>
</body></html>"""
    return html, "generated:inline"

def _vsp_export_v3_send_html_real_v1(html_or_path, mode: str):
    if isinstance(html_or_path, Path):
        body = html_or_path.read_text(encoding="utf-8", errors="replace")
        resp = make_response(body, 200)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-MODE"] = mode
        return resp
    else:
        resp = make_response(html_or_path, 200)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-MODE"] = mode
        return resp

def _vsp_export_v3_make_zip_real_v1(run_dir: str, rid: str):
    tmp = tempfile.NamedTemporaryFile(prefix=f"vsp_export_{rid}_", suffix=".zip", delete=False)
    tmp.close()
    zpath = Path(tmp.name)
    base = Path(run_dir)

    with zipfile.ZipFile(zpath, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for rel in ["report", "findings_unified.json", "findings_unified.csv", "SUMMARY.txt", "runner.log"]:
            p = base / rel
            if not p.exists():
                continue
            if p.is_dir():
                for f in p.rglob("*"):
                    if f.is_file():
                        zf.write(f, arcname=str(f.relative_to(base)))
            else:
                zf.write(p, arcname=str(p.relative_to(base)))
    return zpath

def _vsp_export_v3_make_pdf_real_v1(run_dir: str, rid: str):
    wk = shutil.which("wkhtmltopdf")
    if not wk:
        return None, {"ok": False, "error": "WKHTMLTOPDF_NOT_FOUND"}

    report_dir = Path(run_dir) / "report"
    report_dir.mkdir(parents=True, exist_ok=True)

    html_or_path, mode = _vsp_export_v3_pick_html_real_v1(run_dir)
    if isinstance(html_or_path, Path):
        html_path = html_or_path
    else:
        html_path = report_dir / "export_v3_generated.html"
        html_path.write_text(html_or_path, encoding="utf-8")

    tmp = tempfile.NamedTemporaryFile(prefix=f"vsp_export_{rid}_", suffix=".pdf", delete=False)
    tmp.close()
    pdf_path = Path(tmp.name)

    cmd = [wk, "--quiet", str(html_path), str(pdf_path)]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0 or (not pdf_path.exists()) or pdf_path.stat().st_size < 1000:
        return None, {
            "ok": False,
            "error": "WKHTMLTOPDF_FAILED",
            "rc": r.returncode,
            "stderr_tail": (r.stderr or "")[-2000:],
        }
    return pdf_path, {"ok": True, "mode": mode, "wkhtmltopdf": wk}

# Register routes SAFELY (avoid AssertionError if reloaded)
try:
    _app = app  # app must exist in vsp_demo_app.py
except Exception:
    _app = None

if _app is not None:
    # /vsp4 page (optional fix) - only if not already registered
    if "vsp4_page_commercial_real_v1" not in _app.view_functions:
        def vsp4_page_commercial_real_v1():
            # render your 4-tabs commercial template if exists; else simple message
            try:
                return render_template("vsp_4tabs_commercial_v1.html")
            except Exception:
                return "VSP4 template not found", 404
        _app.add_url_rule("/vsp4", endpoint="vsp4_page_commercial_real_v1", view_func=vsp4_page_commercial_real_v1, methods=["GET"])

    # export v3 route
    if "api_vsp_run_export_v3_commercial_real_v1" not in _app.view_functions:
        def api_vsp_run_export_v3_commercial_real_v1(rid):
            fmt = (request.args.get("fmt") or "").lower().strip()
            probe = request.args.get("probe")

            run_dir, how = _vsp_export_v3_resolve_run_dir_real_v1(rid)
            if not run_dir:
                payload = {"ok": False, "error": "RUN_DIR_NOT_FOUND", "rid": rid, "resolved": None, "how": how}
                return jsonify(payload), 404

            # probe = advertise capability
            if probe:
                wk = shutil.which("wkhtmltopdf")
                return jsonify({
                    "ok": True,
                    "rid": rid,
                    "run_dir": run_dir,
                    "how": how,
                    "available": {"html": True, "zip": True, "pdf": bool(wk)},
                    "wkhtmltopdf": wk
                }), 200

            if fmt in ("", "html"):
                html_or_path, mode = _vsp_export_v3_pick_html_real_v1(run_dir)
                return _vsp_export_v3_send_html_real_v1(html_or_path, mode)

            if fmt == "zip":
                zpath = _vsp_export_v3_make_zip_real_v1(run_dir, rid)
                return send_file(str(zpath), mimetype="application/zip", as_attachment=True, download_name=f"{rid}.zip")

            if fmt == "pdf":
                pdf_path, meta = _vsp_export_v3_make_pdf_real_v1(run_dir, rid)
                if not pdf_path:
                    return jsonify({"ok": False, "rid": rid, **meta}), 501 if meta.get("error") == "WKHTMLTOPDF_NOT_FOUND" else 500
                return send_file(str(pdf_path), mimetype="application/pdf", as_attachment=True, download_name=f"{rid}.pdf")

            return jsonify({"ok": False, "error": "BAD_FMT", "fmt": fmt, "rid": rid}), 400

        _app.add_url_rule(
            "/api/vsp/run_export_v3/<rid>",
            endpoint="api_vsp_run_export_v3_commercial_real_v1",
            view_func=api_vsp_run_export_v3_commercial_real_v1,
            methods=["GET"],
        )

# === VSP_EXPORT_V3_COMMERCIAL_REAL_V1 END ===
PY

python3 -m py_compile "$F"
echo "[OK] patched + py_compile OK => $F"
