#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_early_${TS}"
echo "[BACKUP] $F.bak_exportpdf_early_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "    # === VSP_RUN_EXPORT_V3_PDF_EARLY_RETURN_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# find the run_export_v3 function (common patterns)
# 1) def api_vsp_run_export_v3(...):
# 2) def run_export_v3(...):
m = re.search(r"^def\s+(\w*run_export_v3\w*)\s*\([^)]*\)\s*:\s*$", t, flags=re.M)
if not m:
    # sometimes function name different but decorator has run_export_v3
    m = re.search(r"^def\s+(\w+)\s*\([^)]*\)\s*:\s*$", t, flags=re.M)
    if not m:
        print("[ERR] cannot find any def to patch")
        raise SystemExit(1)

# Better: locate by route string if present
route_pos = t.find("run_export_v3")
if route_pos != -1:
    # try to find nearest def after the route mention
    mm = re.search(r"^def\s+(\w+)\s*\([^)]*\)\s*:\s*$", t[route_pos:], flags=re.M)
    if mm:
        # compute absolute index
        def_line_start = route_pos + mm.start()
    else:
        def_line_start = m.start()
else:
    def_line_start = m.start()

# find end of def line
def_line_end = t.find("\n", def_line_start)
if def_line_end == -1:
    print("[ERR] malformed file (no newline after def)")
    raise SystemExit(1)

# determine indent level of function body (assume 4 spaces)
insert_at = def_line_end + 1

# Insert early-return block immediately after def line (safe).
# It relies on request/jsonify/send_file/glob/os being available in file (they already are in your export logic).
block = """
{TAG}
    try:
        _fmt = (request.args.get("fmt","") or "").lower()
    except Exception:
        _fmt = ""
    if _fmt == "pdf":
        # Resolve run_dir robustly from rid
        try:
            rid_in = rid
        except Exception:
            rid_in = request.view_args.get("rid","") if hasattr(request, "view_args") else ""
        rid_norm = str(rid_in or "")
        # Normalize RUN_VSP_CI_... -> VSP_CI_...
        if rid_norm.startswith("RUN_"):
            rid_norm2 = rid_norm[len("RUN_"):]
        else:
            rid_norm2 = rid_norm

        # Candidate run dirs (keep your current base)
        bases = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY-10-10-v4/out_ci/",
        ]
        cands = []
        for b in bases:
            cands.append(os.path.join(b, rid_norm2))
            cands.append(os.path.join(b, rid_norm))
            # also allow VSP_CI_ prefix if missing
            if "VSP_CI_" not in rid_norm2 and rid_norm2:
                cands.append(os.path.join(b, "VSP_CI_" + rid_norm2))

        run_dir = None
        for c in cands:
            try:
                if os.path.isdir(c):
                    run_dir = c
                    break
            except Exception:
                pass

        # If your existing code already computed run_dir earlier, prefer it
        if "run_dir" in locals() and isinstance(locals().get("run_dir"), str) and os.path.isdir(locals().get("run_dir")):
            run_dir = locals().get("run_dir")

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

        # Not found => commercial: 200 + available=0 (NOT 404)
        rsp = jsonify({
            "ok": True,
            "fmt": "pdf",
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
print("[OK] inserted early-return pdf block into run_export_v3")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo
echo "== restart 8910 (best effort) =="
fuser -k 8910/tcp 2>/dev/null || true
if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] restart script not found; restart gunicorn manually"
fi

echo "[DONE] patch_run_export_v3_pdf_early_return_v1"
