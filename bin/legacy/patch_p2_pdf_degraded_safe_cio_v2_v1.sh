#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] PATCH BE: /api/vsp/run_export_cio_v2 fmt=pdf (wkhtmltopdf degraded-safe) =="
FBE="vsp_demo_app.py"
[ -f "$FBE" ] || { echo "[ERR] missing $FBE"; exit 2; }
cp -f "$FBE" "$FBE.bak_pdf_cio_${TS}" && echo "[BACKUP] $FBE.bak_pdf_cio_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Ensure imports
need = ["import shutil", "import subprocess"]
for imp in need:
    if imp not in s:
        # inject near top after existing imports
        s = re.sub(r'(\nimport [^\n]+\n)', r'\1' + imp + '\n', s, count=1) if re.search(r'\nimport [^\n]+\n', s) else imp + "\n" + s

# Find CIO v2 route function (very tolerant)
# We will inject a pdf branch right after fmt parsing or near the html send_file branch.
pat_func = re.compile(r'(def\s+api_vsp_run_export_cio_v2[^\n]*\n(?:.|\n)*?\n)', re.M)

m = pat_func.search(s)
if not m:
    # fallback: search route decorator usage
    m2 = re.search(r'(@app\.route\([^\)]*run_export_cio_v2[^\)]*\)\s*\n(?:.|\n)*?def\s+([A-Za-z0-9_]+)\s*\()', s)
    if not m2:
        raise SystemExit("[ERR] cannot find CIO v2 route function to patch")
    fn = m2.group(2)
    pat_func = re.compile(r'(def\s+'+re.escape(fn)+r'[^\n]*\n(?:.|\n)*?\n)', re.M)
    m = pat_func.search(s)
    if not m:
        raise SystemExit("[ERR] cannot locate function body for CIO v2 route")

body = m.group(1)

BEGIN="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_BEGIN"
END="    # VSP_CIO_V2_PDF_DEGRADED_SAFE_END"
body = re.sub(re.escape(BEGIN)+r"(?:.|\n)*?"+re.escape(END)+r"\n", "", body)

# Inject block: assumes there is `fmt = ...` somewhere; if not, create it.
if "fmt =" not in body:
    # insert fmt near top of function
    body = re.sub(r'(def\s+[^\n]+\n)', r'\1    fmt = (request.args.get("fmt","html") or "html").lower().strip()\n', body, count=1)

pdf_block = f"""
{BEGIN}
    # commercial: degraded-safe PDF export for CIO v2
    if fmt == "pdf":
        # we expect CIO v2 HTML already exists in RUN_DIR/reports/vsp_run_report_cio_v2.html
        try:
            # "html_path" should exist in existing logic; if not, derive from run_dir + reports
            html_path_local = locals().get("html_path") or locals().get("html_file") or None
            run_dir_local = locals().get("run_dir") or locals().get("RUN_DIR") or None

            if not html_path_local:
                if run_dir_local:
                    html_path_local = str(Path(run_dir_local) / "reports" / "vsp_run_report_cio_v2.html")
            html_path_local = str(html_path_local) if html_path_local else None

            if not html_path_local or not Path(html_path_local).is_file():
                resp = jsonify({{
                    "ok": False,
                    "degraded": True,
                    "reason": "cio_v2_html_missing",
                    "hint": "run vsp_cio_upgrade_v2_one_shot.sh to build reports/vsp_run_report_cio_v2.html"
                }})
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
                return resp, 200

            pdf_path = str(Path(html_path_local).with_suffix(".pdf"))

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

            # build or refresh pdf if missing/older than html
            try:
                need_build = (not Path(pdf_path).is_file()) or (Path(pdf_path).stat().st_mtime < Path(html_path_local).stat().st_mtime)
            except Exception:
                need_build = True

            if need_build:
                # timeout safe
                cmd = [wk, "--quiet", html_path_local, pdf_path]
                subprocess.run(cmd, timeout=45, check=True)

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

# Insert pdf block right after fmt line
body = re.sub(r'(\n\s*fmt\s*=.*\n)', r'\1' + pdf_block + "\n", body, count=1)

s = s[:m.start(1)] + body + s[m.end(1):]
p.write_text(s, encoding="utf-8")
print("[OK] patched CIO v2 route fmt=pdf (degraded-safe)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK => vsp_demo_app.py"

echo
echo "== [2] PATCH RUNS UI: pdf button -> CIO v2 PDF =="
FRUN="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$FRUN" ] || { echo "[ERR] missing $FRUN"; exit 2; }
cp -f "$FRUN" "$FRUN.bak_pdf_cio_${TS}" && echo "[BACKUP] $FRUN.bak_pdf_cio_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace any existing pdf export link to point to CIO v2 PDF
# tolerate many formats: run_export_v3?fmt=pdf, run_export_pdf..., etc.
s = re.sub(
    r'"/api/vsp/[^"]*run_export[^"]*"\s*\+\s*encodeURIComponent\(rid\)\s*\+\s*"\?fmt=pdf"',
    r'"/api/vsp/run_export_cio_v2/" + encodeURIComponent(rid) + "?fmt=pdf"',
    s
)

# Also handle template-literal occurrences: `/api/vsp/...${rid}?fmt=pdf`
s = re.sub(
    r'`/api/vsp/[^`]*run_export[^`]*\$\{[^}]*rid[^}]*\}[^`]*\?fmt=pdf`',
    r'`/api/vsp/run_export_cio_v2/${encodeURIComponent(rid)}?fmt=pdf`',
    s
)

p.write_text(s, encoding="utf-8")
print("[OK] runs pdf now points to CIO v2 PDF")
PY

node --check "$FRUN" >/dev/null && echo "[OK] runs JS syntax OK"
echo
echo "[DONE] P2 PDF degraded-safe applied. Restart 8910 + Hard refresh."
