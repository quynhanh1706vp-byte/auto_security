#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_preempt_v2_${TS}"
echo "[BACKUP] $F.bak_exportpdf_preempt_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_EXPORT_PDF_PREEMPT_V2 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_WSGI_EXPORT_PDF_PREEMPT_V2 ===
import os, glob, json
from urllib.parse import parse_qs

class VspExportPdfPreemptV2:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO", "") or ""
            if path.startswith("/api/vsp/run_export_v3/"):
                qs = environ.get("QUERY_STRING", "") or ""
                q = parse_qs(qs)
                fmt = (q.get("fmt", ["html"])[0] or "html").lower().strip()
                if fmt == "pdf":
                    rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                    rid_norm = rid[4:] if rid.startswith("RUN_") else rid

                    base = os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"
                    ci_dir = os.path.join(base, rid_norm)

                    if not os.path.isdir(ci_dir):
                        ci_dir = ""
                        for d in sorted(glob.glob(os.path.join(base, "VSP_CI_*")), reverse=True):
                            if rid_norm in os.path.basename(d):
                                ci_dir = d
                                break

                    pdf = ""
                    best_m = -1.0
                    if ci_dir:
                        for pat in (os.path.join(ci_dir, "reports", "*.pdf"), os.path.join(ci_dir, "*.pdf")):
                            for f in glob.glob(pat):
                                try:
                                    m = os.path.getmtime(f)
                                except Exception:
                                    continue
                                if m > best_m:
                                    best_m = m
                                    pdf = f

                    if pdf and os.path.isfile(pdf):
                        size = os.path.getsize(pdf)
                        headers = [
                            ("Content-Type", "application/pdf"),
                            ("Content-Disposition", f'attachment; filename="{os.path.basename(pdf)}"'),
                            ("Content-Length", str(size)),
                            ("X-VSP-EXPORT-AVAILABLE", "1"),
                            ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                        ]
                        start_response("200 OK", headers)
                        return open(pdf, "rb")

                    body = json.dumps({
                        "ok": False, "http_code": 404, "error": "PDF_NOT_FOUND",
                        "rid": rid, "rid_norm": rid_norm,
                        "ci_run_dir": ci_dir or None
                    }).encode("utf-8")
                    start_response("404 NOT FOUND", [
                        ("Content-Type", "application/json"),
                        ("Content-Length", str(len(body))),
                        ("X-VSP-EXPORT-AVAILABLE", "0"),
                    ])
                    return [body]
        except Exception as e:
            body = json.dumps({"ok": False, "http_code": 500, "error": "EXPORT_PREEMPT_ERR", "detail": str(e)}).encode("utf-8")
            start_response("500 INTERNAL SERVER ERROR", [
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(body))),
                ("X-VSP-EXPORT-AVAILABLE", "0"),
            ])
            return [body]

        return self.app(environ, start_response)

def _vsp_install_export_pdf_preempt_v2():
    g = globals()
    app = g.get("application", None)
    if app is None:
        return False
    # avoid double wrap
    if isinstance(app, VspExportPdfPreemptV2):
        return True
    g["application"] = VspExportPdfPreemptV2(app)
    try:
        print("[VSP_WSGI_EXPORT_PDF_PREEMPT_V2] installed")
    except Exception:
        pass
    return True
'''

# Insert block near EOF
t = t + "\n\n" + block + "\n"

# Install AFTER the last time "application =" appears (so we wrap the final app actually served)
# We'll append a call at EOF (guaranteed to run at import time).
t = t + "\ntry:\n    _vsp_install_export_pdf_preempt_v2()\nexcept Exception:\n    pass\n"

p.write_text(t, encoding="utf-8")
print("[OK] patched + install call appended")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
