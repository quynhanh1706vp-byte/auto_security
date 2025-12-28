#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [A] confirm wsgi file path =="
python3 - <<'PY'
import wsgi_vsp_ui_gateway, inspect
print("wsgi_vsp_ui_gateway file =", inspect.getfile(wsgi_vsp_ui_gateway))
PY

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_exportpdf_v3_${TS}"
echo "[BACKUP] $F.bak_force_exportpdf_v3_${TS}"

echo "== [B] append EOF preempt installer (cannot be overwritten) =="

python3 - <<'PY'
from pathlib import Path
p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V3 ==="
if TAG in t:
    print("[OK] already installed, skip")
    raise SystemExit(0)

block = r'''
# === VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V3 ===
import os, glob, json
from urllib.parse import parse_qs

class _VspExportPdfPreemptForceV3:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "").strip()
        try:
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
                        start_response("200 OK", [
                            ("Content-Type", "application/pdf"),
                            ("Content-Disposition", f'attachment; filename="{os.path.basename(pdf)}"'),
                            ("Content-Length", str(size)),
                            ("X-VSP-EXPORT-AVAILABLE", "1"),
                            ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                        ])
                        return open(pdf, "rb")

                    body = json.dumps({
                        "ok": False, "http_code": 404,
                        "error": "PDF_NOT_FOUND",
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

def _vsp__install_export_pdf_preempt_force_v3():
    g = globals()
    app = g.get("application", None)
    if app is None:
        return False
    if isinstance(app, _VspExportPdfPreemptForceV3):
        return True
    g["application"] = _VspExportPdfPreemptForceV3(app)
    try:
        print("[VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V3] installed type=", type(g["application"]).__name__)
    except Exception:
        pass
    return True

try:
    _vsp__install_export_pdf_preempt_force_v3()
except Exception:
    pass
'''

p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended FORCE_V3 block at EOF")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [C] restart 8910 =="
rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh

echo "== [D] quick verify headers =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
echo "RID=$RID"
curl -sS -D- -o /dev/null "http://127.0.0.1:8910/api/vsp/run_export_v3/${RID}?fmt=pdf" \
 | grep -iE '^(http/|content-type:|x-vsp-export-available:|x-vsp-export-file:)'
