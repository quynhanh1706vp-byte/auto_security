#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportfix_v2_${TS}"
echo "[BACKUP] $F.bak_exportfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_COMMERCIAL_V2 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# ensure imports
need = ["import glob", "import shutil", "import tempfile", "import subprocess"]
# insert after first import block
if any(x not in s for x in need):
    def ins(m):
        block=m.group(0)
        for x in need:
            if x not in s:
                block += x + "\n"
        return block
    s = re.sub(r'(?m)^(import .+\n)+', ins, s, count=1)

append = r'''
''' + marker + r'''
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

def _vsp_export_try_pdf_wkhtmltopdf(url: str, timeout_sec: int = 180):
    exe = shutil.which("wkhtmltopdf")
    if not exe:
        return None, "wkhtmltopdf_missing"
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".pdf", delete=False)
    tmp.close()
    cmd = [exe, "--quiet", url, tmp.name]
    try:
        subprocess.run(cmd, timeout=timeout_sec, check=True)
        if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name, None
        return None, "wkhtmltopdf_empty_output"
    except Exception as e:
        return None, f"wkhtmltopdf_failed:{type(e).__name__}"

# --- monkey patch: wrap original handler if it exists ---
try:
    _orig_run_export_v3 = run_export_v3  # type: ignore[name-defined]
except Exception:
    _orig_run_export_v3 = None

if _orig_run_export_v3:
    def run_export_v3(rid, *args, **kwargs):  # noqa: F811
        # keep original behavior but fix run_dir resolver + implement pdf
        fmt = (request.args.get("fmt") or "html").lower()
        rid_norm = rid.replace("RUN_", "") if isinstance(rid, str) else str(rid)

        # PDF: implement with wkhtmltopdf from html URL
        if fmt == "pdf":
            base = request.url_root.rstrip("/")
            html_url = f"{base}/api/vsp/run_export_v3/{rid}?fmt=html"
            pdf_path, err = _vsp_export_try_pdf_wkhtmltopdf(html_url, timeout_sec=180)
            if pdf_path:
                resp = send_file(pdf_path, mimetype="application/pdf", as_attachment=True,
                                 download_name=f"{rid_norm}.pdf")
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
                return resp
            resp = jsonify({"ok": False, "error": "pdf_export_failed", "detail": err})
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
            return resp, 500

        # For html/zip: ensure resolver can find correct run_dir via RID
        # (Original handler typically uses run_dir; we pass through, but we also set a global hint if it reads it)
        cand = _vsp_export_resolve_run_dir_best_effort(rid_norm)
        if cand:
            # set env-style hint for downstream if handler uses it
            os.environ["VSP_EXPORT_RUN_DIR_HINT"] = cand

        return _orig_run_export_v3(rid, *args, **kwargs)
'''
s = s.rstrip() + "\n\n" + append + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended commercial wrapper", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
