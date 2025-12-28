#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_ondemand_v2_${TS}"
echo "[BACKUP] $F.bak_export_ondemand_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_ONDEMAND_V2 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) ensure imports (append after first import block)
need = [
  "import zipfile",
  "import tempfile",
  "import subprocess",
  "import shutil",
  "import glob",
  "from datetime import datetime, timezone",
]
def add_imports(text):
    for imp in need:
        if imp not in text:
            text = re.sub(r'(?m)^(import .+\n)+', lambda m: m.group(0)+imp+"\n", text, count=1)
    return text
s = add_imports(s)

# 2) find handler function by route decorator containing run_export_v3
# supports @bp.route("/api/vsp/run_export_v3/<rid>") or similar
route_pat = r'@[\w\.]+\.route\(\s*[\'"][^\'"]*run_export_v3[^\'"]*[\'"][^\)]*\)\s*'
m = re.search(route_pat, s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find route decorator for run_export_v3 in file")

# find next def after the decorator
tail = s[m.end():]
m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(\s*rid\b', tail)
if not m2:
    # fallback: def <name>(rid, ...)
    m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(\s*rid\s*,', tail)
if not m2:
    raise SystemExit("[ERR] cannot find handler def ... (rid...) after decorator")

func_name = m2.group(1)
print("[INFO] detected handler =", func_name)

# 3) inject helpers once at EOF
helpers = r'''
''' + marker + r'''
def _nowz():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z")

def _resolve_run_dir_best_effort(rid_norm: str):
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

def _ensure_report_files(run_dir: str):
    report_dir = os.path.join(run_dir, "report")
    os.makedirs(report_dir, exist_ok=True)
    csv_path = os.path.join(report_dir, "findings_unified.csv")
    json_path = os.path.join(report_dir, "findings_unified.json")
    # if only root findings exists, copy into report/
    root_json = os.path.join(run_dir, "findings_unified.json")
    if (not os.path.isfile(json_path)) and os.path.isfile(root_json):
        try: shutil.copy2(root_json, json_path)
        except Exception: pass
    return report_dir, csv_path, json_path

def _build_export_html(report_dir: str, csv_path: str, json_path: str, rid_norm: str):
    html_path = os.path.join(report_dir, "export_v3.html")
    if os.path.isfile(html_path) and os.path.getsize(html_path) > 0:
        return html_path

    total = 0
    sev_counts, tool_counts = {}, {}
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
        if not d: return "<tr><td colspan='2'>(none)</td></tr>"
        return "\n".join([f"<tr><td>{k}</td><td>{v}</td></tr>" for k,v in sorted(d.items(), key=lambda kv:(-kv[1],kv[0]))])

    html = f"""<!doctype html><html><head><meta charset='utf-8'/>
    <title>VSP Export {rid_norm}</title>
    <style>body{{font-family:Arial;padding:24px}} table{{border-collapse:collapse;width:100%}}
    td,th{{border:1px solid #eee;padding:6px 8px}}</style></head>
    <body>
    <h2>VSP Export v3 - {rid_norm}</h2>
    <p>Generated at: {_nowz()}</p>
    <p><b>Total findings:</b> {total}</p>
    <h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>{rows(sev_counts)}</table>
    <h3>By tool</h3><table><tr><th>Tool</th><th>Count</th></tr>{rows(tool_counts)}</table>
    <p style='margin-top:18px;color:#777'>Commercial on-demand export fallback.</p>
    </body></html>"""
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
        return None, f"wkhtmltopdf_failed:{type(e).__name__}"
'''
s = s.rstrip() + "\n\n" + helpers + "\n"

# 4) insert on-demand block at top of detected handler function
func_def_pat = rf'(?m)^(\s*)def\s+{re.escape(func_name)}\s*\(\s*rid\b[^\)]*\)\s*:'
m3 = re.search(func_def_pat, s)
if not m3:
    raise SystemExit("[ERR] cannot locate function def to patch: " + func_name)

indent = (m3.group(1) or "") + "    "
insert = f"""
{indent}# [COMMERCIAL] on-demand export (fix HTML_NOT_FOUND/ZIP_NOT_FOUND and enable PDF via wkhtmltopdf)
{indent}try:
{indent}    fmt = (request.args.get("fmt") or "html").lower()
{indent}    rid_norm = rid.replace("RUN_","") if isinstance(rid,str) else str(rid)
{indent}    run_dir = _resolve_run_dir_best_effort(rid_norm)
{indent}    if run_dir and os.path.isdir(run_dir):
{indent}        report_dir, csv_path, json_path = _ensure_report_files(run_dir)
{indent}        html_file = _build_export_html(report_dir, csv_path, json_path, rid_norm)
{indent}        if fmt == "html":
{indent}            resp = send_file(html_file, mimetype="text/html", as_attachment=True, download_name=f"{{rid_norm}}.html")
{indent}            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}            resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V2"
{indent}            return resp
{indent}        if fmt == "zip":
{indent}            z = _zip_dir(report_dir)
{indent}            resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=f"{{rid_norm}}.zip")
{indent}            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}            resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V2"
{indent}            return resp
{indent}        if fmt == "pdf":
{indent}            pdf_path, err = _pdf_wkhtmltopdf(html_file, timeout_sec=180)
{indent}            if pdf_path:
{indent}                resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=f"{{rid_norm}}.pdf")
{indent}                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
{indent}                resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V2"
{indent}                return resp
{indent}            resp = jsonify({{"ok": False, "error": "pdf_export_failed", "detail": err, "run_dir": run_dir}})
{indent}            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
{indent}            return resp, 500
{indent}except Exception:
{indent}    pass
"""

# insert right after the def line
pos = m3.end()
s = s[:pos] + "\n" + insert + s[pos:]

p.write_text(s, encoding="utf-8")
print("[OK] patched handler:", func_name)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
