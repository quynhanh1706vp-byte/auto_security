#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportfix_${TS}"
echo "[BACKUP] $F.bak_exportfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="### [COMMERCIAL] EXPORT_V3_FIX_V1 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# add needed imports if missing
imports=[]
if "import glob" not in s: imports.append("import glob")
if "import shutil" not in s: imports.append("import shutil")
if "import tempfile" not in s: imports.append("import tempfile")
if "import subprocess" not in s: imports.append("import subprocess")

if imports:
    # insert after first import block
    s = re.sub(r'(?m)^(import .+\n)+', lambda m: m.group(0) + "".join(x+"\n" for x in imports), s, count=1)

# append helper + wrapper route logic
patch = r'''
''' + marker + r'''
def _vsp_export_resolve_run_dir_best_effort(rid_norm: str):
    """
    Best-effort resolver for CI runs where the real run dir lives under /home/test/Data/*/out_ci/<RID>.
    """
    cands = []
    # common roots
    for g in glob.glob(f"/home/test/Data/*/out_ci/{rid_norm}"):
        cands.append(g)
    # prefer SECURITY-* project roots if exist
    for g in glob.glob(f"/home/test/Data/SECURITY-*/out_ci/{rid_norm}"):
        cands.insert(0, g)
    for x in cands:
        if os.path.isdir(x):
            return x
    return None

def _vsp_export_try_pdf_wkhtmltopdf(url: str, timeout_sec: int = 120):
    exe = shutil.which("wkhtmltopdf")
    if not exe:
        return None, "wkhtmltopdf_missing"
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".pdf", delete=False)
    tmp.close()
    cmd = [exe, "--quiet", url, tmp.name]
    try:
        subprocess.run(cmd, timeout=timeout_sec, check=True)
        if os.path.getsize(tmp.name) > 0:
            return tmp.name, None
        return None, "wkhtmltopdf_empty_output"
    except Exception as e:
        return None, f"wkhtmltopdf_failed:{type(e).__name__}"
'''
s = s.rstrip() + "\n\n" + patch + "\n"

# Now monkey-patch inside existing handler by adding a small prelude and PDF branch hook.
# We look for route function name containing "run_export_v3" and insert fallback run_dir logic after it computes rid_norm/run_dir.
# If not found, we still keep helpers for manual use.
def insert_after(pattern, insert_text):
    nonlocal s
    m = re.search(pattern, s, flags=re.S|re.M)
    if not m:
        return False
    idx = m.end()
    s = s[:idx] + insert_text + s[idx:]
    return True

# Insert run_dir fallback after first occurrence of "rid_norm" assignment OR "run_dir" assignment
fallback_block = r'''
    # [COMMERCIAL] resolve CI run_dir best-effort (fix 404 html/zip when run_dir resolver points wrong place)
    try:
        _rid_norm = rid_norm if "rid_norm" in locals() else (rid.replace("RUN_","") if isinstance(rid,str) else "")
        if ("run_dir" not in locals()) or (not run_dir) or (not os.path.isdir(run_dir)):
            _cand = _vsp_export_resolve_run_dir_best_effort(_rid_norm)
            if _cand:
                run_dir = _cand
    except Exception:
        pass
'''

ok = insert_after(r'(?m)^\s*rid_norm\s*=.*\n', fallback_block)
if not ok:
    ok = insert_after(r'(?m)^\s*run_dir\s*=.*\n', fallback_block)

# Patch PDF branch: if there is a pdf stub returning 501, replace it.
pdf_replaced = False
s2 = re.sub(
    r'(?s)(if\s+fmt\s*==\s*[\'"]pdf[\'"]\s*:\s*)(.*?)(return\s+jsonify\(\{.*?501)',
    r'\1'
    r'    # [COMMERCIAL] generate PDF via wkhtmltopdf from HTML export URL\n'
    r'    try:\n'
    r'        base = request.url_root.rstrip("/")\n'
    r'        html_url = f"{base}/api/vsp/run_export_v3/{rid}?fmt=html"\n'
    r'        pdf_path, err = _vsp_export_try_pdf_wkhtmltopdf(html_url, timeout_sec=180)\n'
    r'        if pdf_path and os.path.isfile(pdf_path):\n'
    r'            resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True,\n'
    r'                           download_name=f"{rid_norm}.pdf")\n'
    r'            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"\n'
    r'            return resp\n'
    r'        return jsonify({"ok": False, "error": "pdf_export_failed", "detail": err}), 500\n'
    r'    except Exception as e:\n'
    r'        return jsonify({"ok": False, "error": "pdf_export_exception", "detail": str(e)}), 500\n'
    r'\3',
    s,
    count=1
)
if s2 != s:
    s = s2
    pdf_replaced = True

p.write_text(s, encoding="utf-8")
print("[OK] patched", p, "pdf_branch_replaced=", pdf_replaced)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
