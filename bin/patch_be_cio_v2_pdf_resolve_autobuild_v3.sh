#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_cio_pdf_fixv3_${TS}" && echo "[BACKUP] $F.bak_cio_pdf_fixv3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Ensure imports exist somewhere
def ensure_import(line):
    global s
    if line not in s:
        m=re.search(r'^(import\s+[^\n]+|from\s+[^\n]+\s+import\s+[^\n]+)\s*$', s, flags=re.M)
        if m:
            ins = m.end()
            s = s[:ins] + "\n" + line + s[ins:]
        else:
            s = line + "\n" + s

ensure_import("import shutil")
ensure_import("import subprocess")
ensure_import("from pathlib import Path")

# Find function def api_vsp_run_export_cio_v2
m = re.search(r'^(def\s+api_vsp_run_export_cio_v2\s*\([^\)]*\)\s*:\s*\n)', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find function def api_vsp_run_export_cio_v2(...) in vsp_demo_app.py")

start = m.start(1)
# slice until next top-level def (col 0) or EOF
m2 = re.search(r'^\s*def\s+[A-Za-z0-9_]+\s*\(', s[m.end(1):], flags=re.M)
end = (m.end(1) + m2.start()) if m2 else len(s)

func = s[start:end]

BEGIN="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_BEGIN"
END="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_END"
func = re.sub(re.escape(BEGIN)+r"[\s\S]*?"+re.escape(END)+r"\n", "", func)

# Ensure fmt exists in func
if re.search(r'^\s*fmt\s*=\s*', func, flags=re.M) is None:
    # inject fmt near top after def line
    func = re.sub(r'^(def\s+api_vsp_run_export_cio_v2[^\n]*\n)', r'\1    fmt = (request.args.get("fmt") or "html").lower().strip()\n', func, count=1, flags=re.M)

pdf_block = f"""
{BEGIN}
    # commercial: PDF export for CIO v2 (resolve run_dir + auto-build HTML if missing)
    if fmt == "pdf":
        try:
            rid_local = rid

            # Resolve RUN_DIR by probing common roots (fast + accurate)
            run_dir_local = None
            for rr in [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
                "/home/test/Data",
            ]:
                cand = Path(rr) / rid_local
                if cand.is_dir():
                    run_dir_local = str(cand)
                    break

            html_path_local = Path(run_dir_local) / "reports" / "vsp_run_report_cio_v2.html" if run_dir_local else None

            # Auto-build HTML if missing
            if not html_path_local or not html_path_local.is_file():
                builder = "/home/test/Data/SECURITY_BUNDLE/bin/vsp_cio_upgrade_v2_one_shot.sh"
                if Path(builder).is_file():
                    subprocess.run(["bash", builder, rid_local], timeout=60, check=False)
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
                subprocess.run([wk, "--quiet", str(html_path_local), pdf_path], timeout=90, check=True)

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

# Insert pdf block right after fmt assignment
func, n = re.subn(r'(^\s*fmt\s*=.*\n)', r'\1'+pdf_block+"\n", func, count=1, flags=re.M)
if n == 0:
    # fallback insert after def line
    func = re.sub(r'^(def\s+api_vsp_run_export_cio_v2[^\n]*\n)', r'\1'+pdf_block+"\n", func, count=1, flags=re.M)

# write back
s = s[:start] + func + s[end:]
p.write_text(s, encoding="utf-8")
print("[OK] patched api_vsp_run_export_cio_v2 fmt=pdf (resolve+autobuild v3)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK => vsp_demo_app.py"
echo "[DONE] Restart 8910 now."
