#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pdf501_${TS}"
echo "[BACKUP] $F.bak_pdf501_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PDF_FORCE_501_V2" in s:
    print("[OK] pdf force 501 already patched, skip")
    raise SystemExit(0)

inject = r'''
# === VSP_PDF_FORCE_501_V2 (commercial) ===
from flask import request as _vsp_req, jsonify as _vsp_jsonify

@app.before_request
def _vsp_block_pdf_export_v2():
    try:
        if _vsp_req.path.startswith("/api/vsp/run_export_v3/"):
            fmt = (_vsp_req.args.get("fmt") or "").lower()
            if fmt == "pdf":
                resp = _vsp_jsonify({
                    "ok": False,
                    "error": "pdf_not_enabled",
                    "message": "PDF export is disabled in this commercial build. Use fmt=html or fmt=zip."
                })
                resp.status_code = 501
                resp.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
                return resp
    except Exception:
        return None
    return None
# === /VSP_PDF_FORCE_501_V2 ===
'''

# append near end (safe)
s2 = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended before_request pdf blocker")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
