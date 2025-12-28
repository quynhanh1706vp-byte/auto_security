#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_override_${TS}"
echo "[BACKUP] $F.bak_export_override_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_OVERRIDE_V3 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure imports exist (append if missing)
need = [
  "import glob",
  "import shutil",
  "import tempfile",
  "import subprocess",
]
for imp in need:
    if imp not in s:
        # put near top after existing imports (simple append after first import block)
        s = re.sub(r'(?m)^(import .+\n)+', lambda m: m.group(0)+imp+"\n", s, count=1)

# Add override route at EOF. It will shadow old route if endpoint name differs; if same, Flask uses last registration
# In your app, export is already available => we re-register with same URL rule string.
append = r'''
''' + marker + r'''
# ---- Commercial override: robust run_dir resolve + wkhtmltopdf PDF ----
def _vsp_export_resolve_run_dir_best_effort(rid_norm: str):
    cands = []
    cands += glob.glob(f"/home/test/Data/SECURITY-*/out_ci/{rid_norm}")
    cands += glob.glob(f"/home/test/Data/*/out_ci/{rid_norm}")
    for x in cands:
        try:
            if os.path.isdir(x):
                return x
        except Exception:
            pass
    return None

def _vsp_export_pick_report_paths(run_dir: str):
    # prefer RUN_DIR/report/*
    rd = os.path.join(run_dir, "report")
    csv1 = os.path.join(rd, "findings_unified.csv")
    json1 = os.path.join(rd, "findings_unified.json")
    # fallback RUN_DIR/*
    csv2 = os.path.join(run_dir, "findings_unified.csv")
    json2 = os.path.join(run_dir, "findings_unified.json")
    return {
        "report_dir": rd,
        "csv": csv1 if os.path.isfile(csv1) else (csv2 if os.path.isfile(csv2) else None),
        "json": json1 if os.path.isfile(json1) else (json2 if os.path.isfile(json2) else None),
    }

def _vsp_export_pdf_wkhtmltopdf_from_html_url(html_url: str, timeout_sec: int = 180):
    exe = shutil.which("wkhtmltopdf")
    if not exe:
        return None, "wkhtmltopdf_missing"
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".pdf", delete=False)
    tmp.close()
    try:
        subprocess.run([exe, "--quiet", html_url, tmp.name], timeout=timeout_sec, check=True)
        if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name, None
        return None, "wkhtmltopdf_empty_output"
    except Exception as e:
        return None, f"wkhtmltopdf_failed:{type(e).__name__}"

# IMPORTANT: override same URL rule
@bp.route("/api/vsp/run_export_v3/<rid>")
def run_export_v3_override_v3(rid):  # noqa: F811
    fmt = (request.args.get("fmt") or "html").lower()
    rid_norm = rid.replace("RUN_", "") if isinstance(rid, str) else str(rid)

    run_dir = None
    # Try existing resolver if present
    try:
        # some versions have get_run_dir_for_rid / resolve_* etc.
        for name in ("get_run_dir_for_rid", "resolve_run_dir_for_rid", "vsp_resolve_run_dir_for_rid"):
            fn = globals().get(name)
            if callable(fn):
                run_dir = fn(rid)
                break
    except Exception:
        run_dir = None

    if (not run_dir) or (not os.path.isdir(str(run_dir))):
        run_dir = _vsp_export_resolve_run_dir_best_effort(rid_norm)

    if not run_dir or not os.path.isdir(run_dir):
        resp = jsonify({"ok": False, "error": "run_dir_not_found", "rid": rid, "rid_norm": rid_norm})
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp, 404

    paths = _vsp_export_pick_report_paths(run_dir)

    if fmt in ("zip", "html"):
        # require at least CSV or JSON
        if not paths["csv"] and not paths["json"]:
            resp = jsonify({
                "ok": False,
                "error": "report_files_missing",
                "need_any_of": ["report/findings_unified.csv", "report/findings_unified.json", "findings_unified.json"],
                "run_dir": run_dir,
                "report_dir": paths["report_dir"],
                "have": {
                    "csv": bool(paths["csv"]),
                    "json": bool(paths["json"]),
                }
            })
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
            return resp, 404

    if fmt == "html":
        # simplest: return the CSV as downloadable HTML-ish fallback if template missing
        # (your existing system likely has better HTML; we keep fallback to avoid 404)
        # if original exporter exists, prefer it:
        orig = globals().get("run_export_v3")
        if callable(orig) and orig is not run_export_v3_override_v3:
            try:
                return orig(rid)
            except Exception:
                pass
        # fallback: serve json
        if paths["json"]:
            resp = send_file(paths["json"], mimetype="application/json", as_attachment=True, download_name=f"{rid_norm}.json")
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = send_file(paths["csv"], mimetype="text/csv", as_attachment=True, download_name=f"{rid_norm}.csv")
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        return resp

    if fmt == "zip":
        # prefer original zip if exists
        orig = globals().get("run_export_v3")
        if callable(orig) and orig is not run_export_v3_override_v3:
            try:
                return orig(rid)
            except Exception:
                pass
        # fallback zip: package report_dir
        tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".zip", delete=False)
        tmp.close()
        import zipfile
        zf = zipfile.ZipFile(tmp.name, "w", compression=zipfile.ZIP_DEFLATED)
        base = paths["report_dir"] if os.path.isdir(paths["report_dir"]) else run_dir
        for root, _, files in os.walk(base):
            for fn in files:
                ap = os.path.join(root, fn)
                rel = os.path.relpath(ap, base)
                zf.write(ap, arcname=rel)
        zf.close()
        resp = send_file(tmp.name, mimetype="application/zip", as_attachment=True, download_name=f"{rid_norm}.zip")
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        return resp

    if fmt == "pdf":
        base = request.url_root.rstrip("/")
        # Render from HTML endpoint (which now at least returns something)
        html_url = f"{base}/api/vsp/run_export_v3/{rid}?fmt=html"
        pdf_path, err = _vsp_export_pdf_wkhtmltopdf_from_html_url(html_url, timeout_sec=180)
        if pdf_path:
            resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=f"{rid_norm}.pdf")
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        resp = jsonify({"ok": False, "error": "pdf_export_failed", "detail": err, "html_url": html_url})
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp, 500

    resp = jsonify({"ok": False, "error": "fmt_not_supported", "fmt": fmt})
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    return resp, 400
'''
s = s.rstrip() + "\n\n" + append + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended override route", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
