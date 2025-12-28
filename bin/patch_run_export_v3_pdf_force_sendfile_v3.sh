#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_force_${TS}"
echo "[BACKUP] $F.bak_exportpdf_force_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "    # === VSP_EXPORT_PDF_FORCE_SENDFILE_V3 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the route decorator for run_export_v3 with <rid>
m = re.search(r"^@app\.route\(\s*['\"]/api/vsp/run_export_v3/<[^>]+>['\"].*\)\s*$", t, flags=re.M)
if not m:
    # fallback: any decorator containing run_export_v3/<
    m = re.search(r"^@.*run_export_v3/<.*$", t, flags=re.M)
if not m:
    print("[ERR] cannot find route decorator for /api/vsp/run_export_v3/<rid>")
    raise SystemExit(1)

# Find the def line immediately after that decorator block
after = t[m.end():]
dm = re.search(r"^\s*def\s+([a-zA-Z0-9_]+)\s*\(([^)]*)\)\s*:\s*$", after, flags=re.M)
if not dm:
    print("[ERR] cannot find def after run_export_v3 route decorator")
    raise SystemExit(1)

def_abs = m.end() + dm.start()
def_line_end = t.find("\n", def_abs)
insert_at = def_line_end + 1

block = """
{TAG}
    # Commercial: for fmt=pdf, ALWAYS try serving a real PDF file if present.
    _fmt = (request.args.get("fmt","") or "").lower()
    if _fmt == "pdf":
        # get rid from function arg if present, else from view_args
        try:
            _rid = rid
        except Exception:
            _rid = (request.view_args or {}).get("rid","")

        rid_norm = str(_rid or "")
        rid_norm2 = rid_norm[4:] if rid_norm.startswith("RUN_") else rid_norm

        # Resolve run_dir deterministically (your known CI base)
        base = "/home/test/Data/SECURITY-10-10-v4/out_ci"
        run_dir = None
        for cand in [
            base + "/" + rid_norm2,
            base + "/" + rid_norm,
        ]:
            try:
                if os.path.isdir(cand):
                    run_dir = cand
                    break
            except Exception:
                pass

        # Collect candidate PDFs
        files = []
        if run_dir:
            globs = [
                os.path.join(run_dir, "report*.pdf"),
                os.path.join(run_dir, "reports", "report*.pdf"),
                os.path.join(run_dir, "*.pdf"),
                os.path.join(run_dir, "reports", "*.pdf"),
            ]
            for g in globs:
                try:
                    files += glob.glob(g)
                except Exception:
                    pass

        files = [f for f in files if isinstance(f, str) and os.path.isfile(f)]
        if files:
            try:
                pick = max(files, key=lambda x: os.path.getmtime(x))
            except Exception:
                pick = files[-1]
            rsp = send_file(pick, mimetype="application/pdf", as_attachment=True, download_name=os.path.basename(pick))
            rsp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
            return rsp

        # If missing -> commercial: 200 json + header 0 (not 404)
        rsp = jsonify({
            "ok": True, "fmt": "pdf",
            "available": 0,
            "rid": rid_norm,
            "rid_norm": rid_norm2,
            "run_dir": run_dir,
            "reason": "pdf_not_found",
        })
        rsp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return rsp
""".replace("{TAG}", TAG)

t2 = t[:insert_at] + block + t[insert_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted forced pdf early-return into correct run_export_v3 handler")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

# restart 8910
fuser -k 8910/tcp 2>/dev/null || true
[ -x bin/restart_8910_gunicorn_commercial_v5.sh ] && bin/restart_8910_gunicorn_commercial_v5.sh || true
echo "[DONE] patch_run_export_v3_pdf_force_sendfile_v3"
