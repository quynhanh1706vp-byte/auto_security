#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

MARK="### [COMMERCIAL] EXPORT_FORCE_BIND_V4 ###"
if grep -qF "$MARK" "$F"; then
  echo "[OK] already patched ($MARK)"
  python3 -m py_compile "$F" && echo "[OK] py_compile OK"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_force_bind_v4_${TS}"
echo "[BACKUP] $F.bak_export_force_bind_v4_${TS}"

cat >> "$F" <<'PY'

### [COMMERCIAL] EXPORT_FORCE_BIND_V4 ###
def _vsp_export_v3_forcefs_impl(rid=None):
    """
    Commercial force-fs export handler for:
      - /api/vsp/run_export_v3/<rid>?fmt=html|zip|pdf
      - /api/vsp/run_export_v3?rid=...&fmt=...
    """
    import os, json, csv, glob, shutil, zipfile, tempfile, subprocess
    from datetime import datetime, timezone
    from flask import request, jsonify, send_file, current_app

    fmt = (request.args.get("fmt") or "zip").lower()
    probe = (request.args.get("probe") or "") == "1"

    # allow rid via query for the non-<rid> route
    if (rid is None) or (str(rid).lower() in ("", "none", "null")):
        rid = request.args.get("rid") or request.args.get("run_id") or request.args.get("id")

    rid_str = "" if rid is None else str(rid)
    rid_norm = rid_str.replace("RUN_", "")

    def nowz():
        return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z")

    def resolve_run_dir_by_status_v2(rid_value: str):
        try:
            fn = current_app.view_functions.get("api_vsp_run_status_v2_winlast_v6")
            if not fn:
                return None
            r = fn(rid_value)
            payload = None
            if isinstance(r, tuple) and len(r) >= 1 and hasattr(r[0], "get_json"):
                payload = r[0].get_json(silent=True)
            elif hasattr(r, "get_json"):
                payload = r.get_json(silent=True)
            if isinstance(payload, dict):
                rd = payload.get("ci_run_dir") or payload.get("ci") or payload.get("run_dir")
                if isinstance(rd, str) and rd and os.path.isdir(rd):
                    return rd
        except Exception:
            return None
        return None

    def resolve_run_dir_fallback(rid_norm_value: str):
        cands = []
        cands += glob.glob("/home/test/Data/SECURITY-*/out_ci/" + rid_norm_value)
        cands += glob.glob("/home/test/Data/*/out_ci/" + rid_norm_value)
        for x in cands:
            try:
                if os.path.isdir(x):
                    return x
            except Exception:
                pass
        return None

    def ensure_report(run_dir: str):
        report_dir = os.path.join(run_dir, "report")
        os.makedirs(report_dir, exist_ok=True)

        src_json = os.path.join(run_dir, "findings_unified.json")
        dst_json = os.path.join(report_dir, "findings_unified.json")
        if os.path.isfile(src_json) and (not os.path.isfile(dst_json)):
            try:
                shutil.copy2(src_json, dst_json)
            except Exception:
                pass

        dst_csv = os.path.join(report_dir, "findings_unified.csv")
        if (not os.path.isfile(dst_csv)) and os.path.isfile(dst_json):
            cols = ["tool","severity","title","file","line","cwe","fingerprint"]
            try:
                d = json.load(open(dst_json, "r", encoding="utf-8"))
                items = d.get("items") or []
                with open(dst_csv, "w", encoding="utf-8", newline="") as f:
                    w = csv.DictWriter(f, fieldnames=cols)
                    w.writeheader()
                    for it in items:
                        cwe = it.get("cwe")
                        if isinstance(cwe, list):
                            cwe = ",".join(cwe)
                        w.writerow({
                            "tool": it.get("tool"),
                            "severity": (it.get("severity_norm") or it.get("severity")),
                            "title": it.get("title"),
                            "file": it.get("file"),
                            "line": it.get("line"),
                            "cwe": cwe,
                            "fingerprint": it.get("fingerprint"),
                        })
            except Exception:
                pass

        html_path = os.path.join(report_dir, "export_v3.html")
        if not (os.path.isfile(html_path) and os.path.getsize(html_path) > 0):
            total = 0
            sev = {}
            try:
                if os.path.isfile(dst_json):
                    d = json.load(open(dst_json, "r", encoding="utf-8"))
                    items = d.get("items") or []
                    total = len(items)
                    for it in items:
                        k = (it.get("severity_norm") or it.get("severity") or "INFO").upper()
                        sev[k] = sev.get(k, 0) + 1
            except Exception:
                pass
            rows = ""
            for k,v in sorted(sev.items(), key=lambda kv:(-kv[1], kv[0])):
                rows += f"<tr><td>{k}</td><td>{v}</td></tr>\n"
            if not rows:
                rows = "<tr><td colspan='2'>(none)</td></tr>"
            html = (
                "<!doctype html><html><head><meta charset='utf-8'/>"
                "<title>VSP Export</title>"
                "<style>body{font-family:Arial;padding:24px} table{border-collapse:collapse;width:100%}"
                "td,th{border:1px solid #eee;padding:6px 8px}</style></head><body>"
                f"<h2>VSP Export v3</h2><p>Generated: {nowz()}</p><p><b>Total findings:</b> {total}</p>"
                "<h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>" + rows + "</table>"
                "</body></html>"
            )
            try:
                with open(html_path, "w", encoding="utf-8") as f:
                    f.write(html)
            except Exception:
                pass

        return report_dir

    def zip_dir(report_dir: str):
        tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".zip", delete=False)
        tmp.close()
        with zipfile.ZipFile(tmp.name, "w", compression=zipfile.ZIP_DEFLATED) as z:
            for root, _, files in os.walk(report_dir):
                for fn in files:
                    ap = os.path.join(root, fn)
                    rel = os.path.relpath(ap, report_dir)
                    z.write(ap, arcname=rel)
        return tmp.name

    def pdf_from_html(html_file: str, timeout_sec: int = 180):
        exe = shutil.which("wkhtmltopdf")
        if not exe:
            return None, "wkhtmltopdf_missing"
        tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".pdf", delete=False)
        tmp.close()
        try:
            subprocess.run([exe, "--quiet", html_file, tmp.name], timeout=timeout_sec, check=True)
            if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:
                return tmp.name, None
            return None, "wkhtmltopdf_empty_output"
        except Exception as ex:
            return None, "wkhtmltopdf_failed:" + type(ex).__name__

    # PROBE must always prove handler is active
    if probe:
        resp = jsonify({
            "ok": True,
            "probe": "EXPORT_FORCE_BIND_V4",
            "rid": rid_str,
            "rid_norm": rid_norm,
            "fmt": fmt
        })
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp

    if not rid_str:
        resp = jsonify({"ok": False, "error": "RID_MISSING"})
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp, 400

    run_dir = resolve_run_dir_by_status_v2(rid_str) or resolve_run_dir_fallback(rid_norm)
    if (not run_dir) or (not os.path.isdir(run_dir)):
        resp = jsonify({"ok": False, "error": "RUN_DIR_NOT_FOUND", "rid": rid_str, "rid_norm": rid_norm})
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp, 404

    report_dir = ensure_report(run_dir)
    html_file = os.path.join(report_dir, "export_v3.html")

    if fmt == "html":
        resp = send_file(html_file, mimetype="text/html", as_attachment=True, download_name=rid_norm + ".html")
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp

    if fmt == "zip":
        zpath = zip_dir(report_dir)
        resp = send_file(zpath, mimetype="application/zip", as_attachment=True, download_name=rid_norm + ".zip")
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp

    if fmt == "pdf":
        pdf_path, err = pdf_from_html(html_file, timeout_sec=180)
        if pdf_path:
            resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=rid_norm + ".pdf")
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
            return resp
        resp = jsonify({"ok": False, "error": "PDF_EXPORT_FAILED", "detail": err})
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
        return resp, 500

    resp = jsonify({"ok": False, "error": "BAD_FMT", "fmt": fmt, "allowed": ["html","zip","pdf"]})
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    resp.headers["X-VSP-EXPORT-MODE"] = "EXPORT_FORCE_BIND_V4"
    return resp, 400


# Bind hard to endpoints (avoid route confusion)
try:
    if "api_vsp_run_export_v3_force_fs" in app.view_functions:
        app.view_functions["api_vsp_run_export_v3_force_fs"] = _vsp_export_v3_forcefs_impl
    if "vsp_run_export_v3" in app.view_functions:
        app.view_functions["vsp_run_export_v3"] = _vsp_export_v3_forcefs_impl
except Exception:
    pass
PY

python3 -m py_compile "$F"
echo "[OK] patched + py_compile OK => $F"
