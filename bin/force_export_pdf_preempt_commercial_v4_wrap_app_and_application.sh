#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_exportpdf_v4_${TS}"
echo "[BACKUP] $F.bak_force_exportpdf_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V4 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V4 ===
import os, glob, json
from urllib.parse import parse_qs

class _VspExportPdfPreemptForceV4:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        # Always mark that wrapper is active (even when delegating)
        def _sr(status, headers, exc_info=None):
            try:
                headers = list(headers or [])
                headers.append(("X-VSP-WSGI-LAYER", "EXPORTPDF_FORCE_V4"))
            except Exception:
                pass
            return start_response(status, headers, exc_info)

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
                        _sr("200 OK", [
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
                    _sr("404 NOT FOUND", [
                        ("Content-Type", "application/json"),
                        ("Content-Length", str(len(body))),
                        ("X-VSP-EXPORT-AVAILABLE", "0"),
                    ])
                    return [body]
        except Exception as e:
            body = json.dumps({"ok": False, "http_code": 500, "error": "EXPORT_PREEMPT_ERR", "detail": str(e)}).encode("utf-8")
            _sr("500 INTERNAL SERVER ERROR", [
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(body))),
                ("X-VSP-EXPORT-AVAILABLE", "0"),
            ])
            return [body]

        return self.inner(environ, _sr)

def _vsp_install_exportpdf_force_v4():
    g = globals()
    # gunicorn may serve either "application" OR "app"
    served = None
    if "application" in g and callable(g["application"]):
        served = "application"
    if served is None and "app" in g and callable(g["app"]):
        served = "app"

    # pick a base callable
    base = g.get("application") if callable(g.get("application", None)) else None
    if base is None and callable(g.get("app", None)):
        base = g["app"]

    if base is None:
        return False

    wrapped = base if isinstance(base, _VspExportPdfPreemptForceV4) else _VspExportPdfPreemptForceV4(base)

    # force both names to point to wrapped (so whichever gunicorn uses, it hits wrapper)
    g["application"] = wrapped
    g["app"] = wrapped

    try:
        print("[VSP_WSGI_EXPORT_PDF_PREEMPT_FORCE_V4] installed served_hint=", served, "type=", type(wrapped).__name__)
    except Exception:
        pass
    return True

try:
    _vsp_install_exportpdf_force_v4()
except Exception:
    pass
'''

p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended FORCE_V4 block at EOF")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
