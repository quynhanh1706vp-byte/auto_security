#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_earlyreturn_v4_${TS}"
echo "[BACKUP] $F.bak_export_earlyreturn_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_EARLYRETURN_V4 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Ensure imports
need = [
  "import zipfile",
  "import tempfile",
  "import subprocess",
  "import shutil",
  "import glob",
  "from datetime import datetime, timezone",
]
m2 = re.search(r'(?ms)^((?:import .+\n|from .+ import .+\n)+)', s)
for imp in need:
    if imp not in s:
        if m2:
            s = s[:m2.end()] + imp + "\n" + s[m2.end():]
        else:
            s = imp + "\n" + s

# Helpers (idempotent by marker)
helpers = f"""
{marker}
def _nowz():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z")

def _resolve_run_dir_best_effort(rid_norm: str):
    cands = []
    cands += glob.glob(f"/home/test/Data/SECURITY-*/out_ci/{{rid_norm}}")
    cands += glob.glob(f"/home/test/Data/*/out_ci/{{rid_norm}}")
    for x in cands:
        try:
            if os.path.isdir(x):
                return x
        except Exception:
            pass
    return None

def _ensure_report_dir(run_dir: str):
    report_dir = os.path.join(run_dir, "report")
    os.makedirs(report_dir, exist_ok=True)
    # copy root findings into report if needed
    root_json = os.path.join(run_dir, "findings_unified.json")
    rep_json  = os.path.join(report_dir, "findings_unified.json")
    if os.path.isfile(root_json) and (not os.path.isfile(rep_json)):
        try: shutil.copy2(root_json, rep_json)
        except Exception: pass
    return report_dir

def _build_export_html_min(report_dir: str, rid_norm: str):
    html_path = os.path.join(report_dir, "export_v3.html")
    if os.path.isfile(html_path) and os.path.getsize(html_path) > 0:
        return html_path
    json_path = os.path.join(report_dir, "findings_unified.json")
    total = 0
    sev_counts, tool_counts = {{}}, {{}}
    if os.path.isfile(json_path):
        try:
            data = json.load(open(json_path, "r", encoding="utf-8"))
            items = data.get("items") or []
            total = len(items)
            for it in items:
                sev = (it.get("severity_norm") or it.get("severity") or "INFO").upper()
                tool = (it.get("tool") or "UNKNOWN").upper()
                sev_counts[sev] = sev_counts.get(sev, 0) + 1
                tool_counts[tool] = tool_counts.get(tool, 0) + 1
        except Exception:
            pass

    def rows(d):
        if not d:
            return "<tr><td colspan='2'>(none)</td></tr>"
        return "\\n".join([f"<tr><td>{{k}}</td><td>{{v}}</td></tr>" for k,v in sorted(d.items(), key=lambda kv:(-kv[1],kv[0]))])

    html = f\"\"\"<!doctype html><html><head><meta charset='utf-8'/>
    <title>VSP Export {{rid_norm}}</title>
    <style>body{{font-family:Arial;padding:24px}} table{{border-collapse:collapse;width:100%}}
    td,th{{border:1px solid #eee;padding:6px 8px}}</style></head>
    <body>
    <h2>VSP Export v3 - {{rid_norm}}</h2>
    <p>Generated at: {{_nowz()}}</p>
    <p><b>Total findings:</b> {{total}}</p>
    <h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>{{rows(sev_counts)}}</table>
    <h3>By tool</h3><table><tr><th>Tool</th><th>Count</th></tr>{{rows(tool_counts)}}</table>
    </body></html>\"\"\"
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)
    return html_path

def _zip_dir(src_dir: str):
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".zip", delete=False)
    tmp.close()
    with zipfile.ZipFile(tmp.name, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(src_dir):
            for fn in files:
                ap = os.path.join(root, fn)
                rel = os.path.relpath(ap, src_dir)
                z.write(ap, arcname=rel)
    return tmp.name

def _pdf_wkhtmltopdf(html_file: str, timeout_sec: int = 180):
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
    except Exception as e:
        return None, f"wkhtmltopdf_failed:{{type(e).__name__}}"
"""
if marker not in s:
    s = s.rstrip() + "\n\n" + helpers + "\n"

# Insert early-return block right after def run_export_v3(...):
m = re.search(r'(?m)^(\s*)def\s+run_export_v3\s*\(\s*rid\b[^\)]*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def run_export_v3(rid...)")

base = m.group(1)
indent = base + "    "

early = f"""
{indent}# [COMMERCIAL] early-return export override (HTML/ZIP/PDF)
{indent}fmt = (request.args.get("fmt") or "html").lower()
{indent}if fmt in ("html","zip","pdf"):
{indent}    rid_norm = rid.replace("RUN_","") if isinstance(rid, str) else str(rid)
{indent}    # prefer ci_run_dir if present in scope; else best-effort locate
{indent}    run_dir = locals().get("ci_run_dir") if "ci_run_dir" in locals() else None
{indent}    if not run_dir or (not os.path.isdir(str(run_dir))):
{indent}        run_dir = _resolve_run_dir_best_effort(rid_norm)
{indent}    if not run_dir or (not os.path.isdir(str(run_dir))):
{indent}        resp = jsonify({{"ok": False, "error": "run_dir_not_found", "rid_norm": rid_norm}})
{indent}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{indent}        resp.headers["X-VSP-EXPORT-MODE"] = "EARLYRETURN_V4"
{indent}        return resp, 404
{indent}    report_dir = _ensure_report_dir(str(run_dir))
{indent}    html_file = _build_export_html_min(report_dir, rid_norm)
{indent}    if fmt == "html":
{indent}        resp = send_file(html_file, mimetype="text/html", as_attachment=True, download_name=f"{{rid_norm}}.html")
{indent}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}        resp.headers["X-VSP-EXPORT-MODE"] = "EARLYRETURN_V4"
{indent}        return resp
{indent}    if fmt == "zip":
{indent}        z = _zip_dir(report_dir)
{indent}        resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=f"{{rid_norm}}.zip")
{indent}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}        resp.headers["X-VSP-EXPORT-MODE"] = "EARLYRETURN_V4"
{indent}        return resp
{indent}    # pdf
{indent}    pdf_path, err = _pdf_wkhtmltopdf(html_file, timeout_sec=180)
{indent}    if pdf_path:
{indent}        resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=f"{{rid_norm}}.pdf")
{indent}        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}        resp.headers["X-VSP-EXPORT-MODE"] = "EARLYRETURN_V4"
{indent}        return resp
{indent}    resp = jsonify({{"ok": False, "error": "pdf_export_failed", "detail": err}})
{indent}    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{indent}    resp.headers["X-VSP-EXPORT-MODE"] = "EARLYRETURN_V4"
{indent}    return resp, 500
"""

# splice after def line
pos = m.end()
s = s[:pos] + "\n" + early + s[pos:]

p.write_text(s, encoding="utf-8")
print("[OK] inserted early-return export block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
