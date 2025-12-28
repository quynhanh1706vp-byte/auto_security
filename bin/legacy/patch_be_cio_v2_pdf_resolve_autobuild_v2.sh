#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_cio_pdf_fix_${TS}" && echo "[BACKUP] $F.bak_cio_pdf_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Ensure imports
for imp in ["import shutil", "import subprocess", "from pathlib import Path"]:
    if imp not in s:
        # insert after first import line
        s = re.sub(r'(\nimport [^\n]+\n)', r'\1'+imp+'\n', s, count=1)

# Locate CIO v2 route function body
m = re.search(r'@app\.route\([^\)]*run_export_cio_v2[^\)]*\)\s*\n(?:@[^\n]*\n)*def\s+([A-Za-z0-9_]+)\s*\([^\)]*\):', s)
if not m:
    raise SystemExit("[ERR] cannot find run_export_cio_v2 route decorator")
fn = m.group(1)

# Extract function block (best-effort): from def fn to next "\ndef " at same indent
pat = re.compile(r'(def\s+'+re.escape(fn)+r'\s*\([^\)]*\):\n)([\s\S]*?)(?=\n(?:(?:@app\.route)|def\s+)[A-Za-z0-9_]+\s*\(|\Z)', re.M)
mm = pat.search(s)
if not mm:
    raise SystemExit("[ERR] cannot slice CIO v2 function body")
head, body = mm.group(1), mm.group(2)

BEGIN="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_BEGIN"
END="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_END"
body = re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n", "", body)

# We want to inject AFTER run_dir/html_path is resolved.
# Find first assignment to run_dir or html_path.
insert_at = None
for keypat in [
    r'^\s*run_dir\s*=\s*.*$',
    r'^\s*ci_run_dir\s*=\s*.*$',
    r'^\s*html_path\s*=\s*.*$',
    r'^\s*html_file\s*=\s*.*$',
]:
    m2 = re.search(keypat, body, flags=re.M)
    if m2:
        # insert after this line
        insert_at = m2.end()
        break

# If no obvious anchor, inject right after fmt line (but we will resolve run_dir ourselves robustly)
if insert_at is None:
    mfmt = re.search(r'^\s*fmt\s*=\s*.*$', body, flags=re.M)
    insert_at = mfmt.end() if mfmt else 0

pdf_block = f"""
{BEGIN}
    # commercial: PDF export for CIO v2 (resolve run_dir + auto-build HTML if missing)
    if fmt == "pdf":
        try:
            rid_local = rid
            # 1) resolve RUN_DIR (fast paths)
            run_dir_local = locals().get("run_dir") or locals().get("ci_run_dir") or None
            if not run_dir_local:
                roots = [
                    "/home/test/Data/SECURITY-10-10-v4/out_ci",
                    "/home/test/Data/SECURITY_BUNDLE/out_ci",
                    "/home/test/Data/SECURITY_BUNDLE/out",
                    "/home/test/Data",
                ]
                for r in roots:
                    cand = Path(r) / rid_local
                    if cand.is_dir():
                        run_dir_local = str(cand)
                        break

            # 2) expected HTML path
            html_path_local = Path(run_dir_local) / "reports" / "vsp_run_report_cio_v2.html" if run_dir_local else None

            # 3) auto-build HTML if missing
            if not html_path_local or not html_path_local.is_file():
                builder = "/home/test/Data/SECURITY_BUNDLE/bin/vsp_cio_upgrade_v2_one_shot.sh"
                if Path(builder).is_file():
                    try:
                        subprocess.run(["bash", builder, rid_local], timeout=45, check=False)
                    except Exception:
                        pass
                # re-check
                if not html_path_local or not html_path_local.is_file():
                    resp = jsonify({{
                        "ok": False,
                        "degraded": True,
                        "reason": "cio_v2_html_missing",
                        "hint": "run vsp_cio_upgrade_v2_one_shot.sh to build reports/vsp_run_report_cio_v2.html",
                        "run_dir": run_dir_local
                    }})
                    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
                    return resp, 200

            # 4) wkhtmltopdf
            wk = shutil.which("wkhtmltopdf")
            if not wk:
                resp = jsonify({{
                    "ok": False,
                    "degraded": True,
                    "reason": "wkhtmltopdf_missing",
                    "hint": "apt install wkhtmltopdf (or keep HTML export)"
                }})
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
                return resp, 200

            pdf_path = str(html_path_local.with_suffix(".pdf"))
            need_build = (not Path(pdf_path).is_file()) or (Path(pdf_path).stat().st_mtime < html_path_local.stat().st_mtime)

            if need_build:
                subprocess.run([wk, "--quiet", str(html_path_local), pdf_path], timeout=60, check=True)

            resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=False, download_name=Path(pdf_path).name)
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return resp
        except subprocess.TimeoutExpired:
            resp = jsonify({{"ok": False, "degraded": True, "reason": "wkhtmltopdf_timeout"}})
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
            return resp, 200
        except Exception as e:
            resp = jsonify({{"ok": False, "degraded": True, "reason": "wkhtmltopdf_error", "error": str(e)}})
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
            return resp, 200
{END}
"""

body = body[:insert_at] + "\n" + pdf_block + "\n" + body[insert_at:]

# write back
new_func = head + body
s = s[:mm.start()] + new_func + s[mm.end():]
p.write_text(s, encoding="utf-8")
print("[OK] patched CIO v2 pdf: resolve run_dir + auto-build html")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK => vsp_demo_app.py"
echo "[DONE] BE patch applied. Restart 8910."
