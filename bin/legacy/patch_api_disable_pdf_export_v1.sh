#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_disablepdf_${TS}"
echo "[BACKUP] $F.bak_disablepdf_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# idempotent marker
if "VSP_PDF_DISABLED_V1" in s:
    print("[OK] PDF disable already patched, skip")
    raise SystemExit(0)

# find export handler
m = re.search(r"def\s+(api_vsp_run_export_v3|run_export_v3)\s*\(", s)
if not m:
    # fallback: search route string
    m = re.search(r"/api/vsp/run_export_v3", s)
    if not m:
        print("[ERR] cannot locate run_export_v3 handler in vsp_demo_app.py")
        raise SystemExit(2)

# Try to inject inside function body if we matched def...
if m.group(0).startswith("def"):
    # locate function block start
    start = m.start()
    # find next line after def
    def_line_end = s.find("\n", start)
    if def_line_end < 0:
        raise SystemExit(3)
    # infer indent of body (assume 4 spaces)
    inject = """
    # === VSP_PDF_DISABLED_V1 ===
    try:
        _fmt = (request.args.get("fmt") or "html").lower()
    except Exception:
        _fmt = "html"
    if _fmt == "pdf":
        resp = jsonify({
            "ok": False,
            "error": "pdf_not_enabled",
            "message": "PDF export is disabled in this commercial build. Use fmt=html or fmt=zip."
        })
        resp.status_code = 501
        resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return resp
    # === /VSP_PDF_DISABLED_V1 ===

"""
    # inject right after def line
    s2 = s[:def_line_end+1] + inject + s[def_line_end+1:]
else:
    # if only route string matched, append a safe helper route (last resort)
    inject = """
# === VSP_PDF_DISABLED_V1 (fallback route wrapper) ===
@app.after_request
def _vsp_disable_pdf_after_request(resp):
    try:
        from flask import request as _r
        if _r.path.startswith("/api/vsp/run_export_v3") and (_r.args.get("fmt","").lower() == "pdf"):
            resp.status_code = 501
            resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
    except Exception:
        pass
    return resp
# === /VSP_PDF_DISABLED_V1 ===
"""
    s2 = s.rstrip() + "\n\n" + inject + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched PDF disable (501)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
