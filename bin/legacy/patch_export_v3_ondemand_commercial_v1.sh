#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_ondemand_${TS}"
echo "[BACKUP] $F.bak_export_ondemand_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_ONDEMAND_V1 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# ensure imports
need_imports = [
    "import zipfile",
    "import tempfile",
    "import subprocess",
    "import shutil",
    "import glob",
    "from datetime import datetime, timezone",
]
for imp in need_imports:
    if imp not in s:
        s = re.sub(r'(?m)^(import .+\n)+', lambda m: m.group(0) + imp + "\n", s, count=1)

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
    # prefer RUN_DIR/report/*
    report_dir = os.path.join(run_dir, "report")
    csv_path = os.path.join(report_dir, "findings_unified.csv")
    json_path = os.path.join(report_dir, "findings_unified.json")
    # fallback: if only root findings_unified.json exists, copy into report/
    root_json = os.path.join(run_dir, "findings_unified.json")
    os.makedirs(report_dir, exist_ok=True)
    if (not os.path.isfile(json_path)) and os.path.isfile(root_json):
        try:
            shutil.copy2(root_json, json_path)
        except Exception:
            pass
    return report_dir, csv_path, json_path

def _build_export_html(report_dir: str, csv_path: str, json_path: str, rid_norm: str):
    html_path = os.path.join(report_dir, "export_v3.html")
    # If already exists, keep
    if os.path.isfile(html_path) and os.path.getsize(html_path) > 0:
        return html_path

    sev_counts = {}
    tool_counts = {}
    total = 0
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
        return "\n".join([f"<tr><td>{k}</td><td>{v}</td></tr>" for k,v in sorted(d.items(), key=lambda kv:(-kv[1],kv[0]))])

    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>VSP Export {rid_norm}</title>
  <style>
    body{{font-family:Arial, sans-serif; padding:24px;}}
    .k{{display:flex; gap:16px; flex-wrap:wrap;}}
    .card{{border:1px solid #ddd; border-radius:10px; padding:14px 16px; min-width:220px;}}
    table{{border-collapse:collapse; width:100%;}}
    td,th{{border:1px solid #eee; padding:6px 8px;}}
  </style>
</head>
<body>
  <h2>VSP Export (v3) - {rid_norm}</h2>
  <p>Generated at: {_nowz()}</p>

  <div class="k">
    <div class="card"><b>Total findings</b><div style="font-size:22px">{total}</div></div>
    <div class="card"><b>Artifacts</b><div>
      {"<a href='findings_unified.csv'>findings_unified.csv</a><br/>" if os.path.isfile(csv_path) else ""}
      {"<a href='findings_unified.json'>findings_unified.json</a><br/>" if os.path.isfile(json_path) else ""}
    </div></div>
  </div>

  <h3>By severity</h3>
  <table><tr><th>Severity</th><th>Count</th></tr>{rows(sev_counts) or "<tr><td colspan='2'>(none)</td></tr>"}</table>

  <h3>By tool</h3>
  <table><tr><th>Tool</th><th>Count</th></tr>{rows(tool_counts) or "<tr><td colspan='2'>(none)</td></tr>"}</table>

  <p style="margin-top:18px;color:#777;">Commercial on-demand export fallback.</p>
</body>
</html>"""
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

# Patch inside existing run_export_v3: we insert an early on-demand handling block at the START of the function body.
m = re.search(r'(?m)^def\s+run_export_v3\s*\(\s*rid\s*\)\s*:\s*$', s)
if not m:
    # sometimes signature differs: def run_export_v3(rid):
    m = re.search(r'(?m)^def\s+run_export_v3\s*\(\s*rid[^)]*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def run_export_v3(...) in file")

# find insertion point = next line after def
start = m.end()
# find the indentation of first line inside function (assume 4 spaces)
insert = r'''
    # [COMMERCIAL] on-demand export (fix HTML_NOT_FOUND/ZIP_NOT_FOUND and enable PDF via wkhtmltopdf)
    try:
        fmt = (request.args.get("fmt") or "html").lower()
        rid_norm = rid.replace("RUN_", "") if isinstance(rid, str) else str(rid)

        run_dir = None
        # reuse existing computed ci_run_dir/run_dir if present later, but we can resolve now:
        run_dir = _resolve_run_dir_best_effort(rid_norm)

        if run_dir and os.path.isdir(run_dir):
            report_dir, csv_path, json_path = _ensure_report_files(run_dir)
            html_file = _build_export_html(report_dir, csv_path, json_path, rid_norm)

            if fmt == "html":
                resp = send_file(html_file, mimetype="text/html", as_attachment=True, download_name=f"{rid_norm}.html")
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
                resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V1"
                return resp

            if fmt == "zip":
                z = _zip_dir(report_dir)
                resp = send_file(z, mimetype="application/zip", as_attachment=True, download_name=f"{rid_norm}.zip")
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
                resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V1"
                return resp

            if fmt == "pdf":
                pdf_path, err = _pdf_wkhtmltopdf(html_file, timeout_sec=180)
                if pdf_path:
                    resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True, download_name=f"{rid_norm}.pdf")
                    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
                    resp.headers["X-VSP-EXPORT-MODE"] = "ONDEMAND_V1"
                    return resp
                resp = jsonify({"ok": False, "error": "pdf_export_failed", "detail": err, "rid_norm": rid_norm, "run_dir": run_dir})
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
                return resp, 500
    except Exception:
        # fallback to original implementation below
        pass
'''

# Insert right after the def line (safe)
s = s[:start] + "\n" + insert + s[start:]

p.write_text(s, encoding="utf-8")
print("[OK] inserted on-demand block into run_export_v3")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
