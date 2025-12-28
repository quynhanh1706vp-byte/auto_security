#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# find the file that defines api_vsp_run_export_v3_force_fs
F="$(grep -RIl --include='*.py' -E 'def\s+api_vsp_run_export_v3_force_fs\s*\(' . | head -n1 || true)"
[ -n "${F:-}" ] || { echo "[ERR] cannot find def api_vsp_run_export_v3_force_fs(...)" ; exit 2; }
echo "[INFO] target=$F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_forcefs_export_${TS}"
echo "[BACKUP] $F.bak_forcefs_export_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("""'"$F"'""")
s = p.read_text(encoding="utf-8", errors="replace")

# ensure imports (best-effort)
need_imports = [
  "import os",
  "import json",
  "import csv",
  "import glob",
  "import shutil",
  "import zipfile",
  "import tempfile",
  "import subprocess",
  "from datetime import datetime, timezone",
]
for imp in need_imports:
    if imp not in s:
        s = imp + "\n" + s

marker = "### [COMMERCIAL] FORCE_FS_EXPORT_V1 ###"
if marker not in s:
    s += f"""

{marker}
def _nowz_v1():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z")

def _find_run_dir_v1(rid_norm: str):
    # strict candidates
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

def _ensure_report_v1(run_dir: str):
    report_dir = os.path.join(run_dir, "report")
    os.makedirs(report_dir, exist_ok=True)

    # ensure findings_unified.json in report/
    src_json = os.path.join(run_dir, "findings_unified.json")
    dst_json = os.path.join(report_dir, "findings_unified.json")
    if os.path.isfile(src_json) and (not os.path.isfile(dst_json)):
        try:
            shutil.copy2(src_json, dst_json)
        except Exception:
            pass

    # ensure findings_unified.csv in report/
    dst_csv = os.path.join(report_dir, "findings_unified.csv")
    if (not os.path.isfile(dst_csv)) and os.path.isfile(dst_json):
        cols = ["tool","severity","title","file","line","cwe","fingerprint"]
        try:
            data = json.load(open(dst_json, "r", encoding="utf-8"))
            items = data.get("items") or []
            with open(dst_csv, "w", encoding="utf-8", newline="") as f:
                w = csv.DictWriter(f, fieldnames=cols)
                w.writeheader()
                for it in items:
                    w.writerow({
                        "tool": it.get("tool"),
                        "severity": it.get("severity_norm") or it.get("severity"),
                        "title": it.get("title"),
                        "file": it.get("file"),
                        "line": it.get("line"),
                        "cwe": ",".join(it.get("cwe") or []) if isinstance(it.get("cwe"), list) else it.get("cwe"),
                        "fingerprint": it.get("fingerprint"),
                    })
        except Exception:
            pass

    # ensure export html in report/
    html_path = os.path.join(report_dir, "export_v3.html")
    if not (os.path.isfile(html_path) and os.path.getsize(html_path) > 0):
        total = 0
        sev_counts = {}
        try:
            if os.path.isfile(dst_json):
                d = json.load(open(dst_json, "r", encoding="utf-8"))
                items = d.get("items") or []
                total = len(items)
                for it in items:
                    sev = (it.get("severity_norm") or it.get("severity") or "INFO").upper()
                    sev_counts[sev] = sev_counts.get(sev, 0) + 1
        except Exception:
            pass
        def rows(d):
            if not d:
                return "<tr><td colspan='2'>(none)</td></tr>"
            return "\\n".join([f"<tr><td>{k}</td><td>{v}</td></tr>" for k,v in sorted(d.items(), key=lambda kv:(-kv[1],kv[0]))])
        html = f\"\"\"<!doctype html><html><head><meta charset='utf-8'/>
<title>VSP Export</title>
<style>body{{font-family:Arial;padding:24px}} table{{border-collapse:collapse;width:100%}}
td,th{{border:1px solid #eee;padding:6px 8px}}</style></head>
<body>
<h2>VSP Export v3</h2>
<p>Generated at: {_nowz_v1()}</p>
<p><b>Total findings:</b> {total}</p>
<h3>By severity</h3>
<table><tr><th>Severity</th><th>Count</th></tr>{rows(sev_counts)}</table>
</body></html>\"\"\"
        try:
            with open(html_path, "w", encoding="utf-8") as f:
                f.write(html)
        except Exception:
            pass

    return report_dir

def _zip_report_v1(report_dir: str):
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".zip", delete=False)
    tmp.close()
    with zipfile.ZipFile(tmp.name, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(report_dir):
            for fn in files:
                ap = os.path.join(root, fn)
                rel = os.path.relpath(ap, report_dir)
                z.write(ap, arcname=rel)
    return tmp.name

def _pdf_from_html_wk_v1(html_file: str, timeout_sec: int = 180):
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
"""

# Replace function body of api_vsp_run_export_v3_force_fs
m = re.search(r'(?m)^(?P<ind>\s*)def\s+api_vsp_run_export_v3_force_fs\s*\(.*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find function def in target")

ind = m.group("ind")
start = m.end()

# find end of function: next "def " or "@..." at same indent
lines = s[start:].splitlines(True)
end_off = 0
for i,ln in enumerate(lines):
    if re.match(rf'^{re.escape(ind)}(def\s+|@)', ln):
        break
    end_off += len(ln)
end = start + end_off

new_body = f"""
{ind}    # {marker} on-demand exporter (html/zip/pdf)
{ind}    fmt = (request.args.get("fmt") or "zip").lower()
{ind}    rid_norm = rid.replace("RUN_","") if isinstance(rid, str) else str(rid)

{ind}    run_dir = _find_run_dir_v1(rid_norm)
{ind}    if not run_dir or (not os.path.isdir(run_dir)):
{ind}        resp = jsonify({{"ok": False, "error": "run_dir_not_found", "rid_norm": rid_norm}})
{ind}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{ind}        resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}        return resp, 404

{ind}    report_dir = _ensure_report_v1(run_dir)
{ind}    html_file = os.path.join(report_dir, "export_v3.html")

{ind}    if fmt == "html":
{ind}        resp = send_file(html_file, mimetype="text/html", as_attachment=True, download_name=f"{{rid_norm}}.html")
{ind}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{ind}        resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}        return resp

{ind}    if fmt == "zip":
{ind}        z = _zip_report_v1(report_dir)
{ind}        resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=f"{{rid_norm}}.zip")
{ind}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{ind}        resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}        return resp

{ind}    if fmt == "pdf":
{ind}        pdf_path, err = _pdf_from_html_wk_v1(html_file, timeout_sec=180)
{ind}        if pdf_path:
{ind}            resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=f"{{rid_norm}}.pdf")
{ind}            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{ind}            resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}            return resp
{ind}        resp = jsonify({{"ok": False, "error": "pdf_export_failed", "detail": err}})
{ind}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{ind}        resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}        return resp, 500

{ind}    resp = jsonify({{"ok": False, "error": "bad_fmt", "fmt": fmt, "allowed": ["html","zip","pdf"]}})
{ind}    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{ind}    resp.headers["X-VSP-EXPORT-MODE"] = "FORCE_FS_V1"
{ind}    return resp, 400
"""

s2 = s[:start] + "\n" + new_body + "\n" + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched api_vsp_run_export_v3_force_fs body in", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
