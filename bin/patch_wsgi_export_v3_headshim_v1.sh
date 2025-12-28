#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_headshim_${TS}"
echo "[BACKUP] $F.bak_export_headshim_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_WSGI_EXPORT_V3_HEADSHIM_V1"
if TAG in t:
    print("[OK] already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_WSGI_EXPORT_V3_HEADSHIM_V1 ===
def _vsp_wsgi_export_v3_headshim_v1(app):
    if getattr(app, "_vsp_wrapped_export_headshim_v1", False):
        return app
    setattr(app, "_vsp_wrapped_export_headshim_v1", True)

    import json
    from pathlib import Path
    from urllib.parse import parse_qs

    _resolve = globals().get("_vsp_resolve_ci_run_dir", None)
    if _resolve is None:
        def _resolve(rid: str):
            key = (rid or "").strip()
            if key.startswith("RUN_"):
                key = key[len("RUN_"):]
            bases = [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            ]
            for b in bases:
                d = Path(b) / key
                if d.is_dir():
                    return d
            return None

    def _pick_file(run_dir: Path, fmt: str):
        fmt = (fmt or "html").lower().strip()
        # canonical names
        if fmt == "html":
            cands = [run_dir/"reports"/"vsp_run_report_cio_v3.html"]
        elif fmt == "zip":
            cands = [run_dir/"reports"/"report.zip", run_dir/"reports"/"vsp_report.zip"]
        elif fmt == "pdf":
            cands = [run_dir/"reports"/"vsp_run_report_cio_v3.pdf"]
        else:
            cands = []
        for fp in cands:
            try:
                if fp.is_file() and fp.stat().st_size > 0:
                    return fp, fmt
            except Exception:
                pass
        return None, fmt

    def _head_resp(start_response, avail: bool, fmt: str, fp: Path|None, rid: str, run_dir: Path|None):
        hdrs = [
            ("Cache-Control","no-store"),
            ("X-VSP-EXPORT-AVAILABLE", "1" if avail else "0"),
            ("X-VSP-EXPORT-FMT", fmt),
        ]
        if avail and fp is not None:
            if fmt == "html":
                hdrs += [("Content-Type","text/html; charset=utf-8"),
                         ("Content-Disposition", f'inline; filename={fp.name}'),
                         ("Content-Length", str(fp.stat().st_size))]
            elif fmt == "zip":
                hdrs += [("Content-Type","application/zip"),
                         ("Content-Disposition", f'attachment; filename={fp.name}'),
                         ("Content-Length", str(fp.stat().st_size))]
            elif fmt == "pdf":
                hdrs += [("Content-Type","application/pdf"),
                         ("Content-Disposition", f'inline; filename={fp.name}'),
                         ("Content-Length", str(fp.stat().st_size))]
            start_response("200 OK", hdrs)
            return [b""]
        # not available -> still 200, no noise
        start_response("200 OK", hdrs + [("Content-Type","application/json; charset=utf-8")])
        return [b""]

    def _wrapped(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_export_v3/"):
            return app(environ, start_response)

        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
        qs = parse_qs(environ.get("QUERY_STRING","") or "")
        fmt = (qs.get("fmt", ["html"])[0] or "html").strip()

        run_dir = _resolve(rid)
        if not run_dir:
            # for HEAD, still return 200 to avoid UI spam; available=0
            if method == "HEAD":
                return _head_resp(start_response, False, fmt, None, rid, None)
            body = json.dumps({"ok": False, "http_code": 404, "error":"run_not_found", "rid": rid}).encode("utf-8")
            start_response("404 NOT FOUND", [("Content-Type","application/json; charset=utf-8"),
                                            ("Content-Length", str(len(body))),
                                            ("Cache-Control","no-store")])
            return [body]

        run_dir = Path(run_dir)
        fp, fmt2 = _pick_file(run_dir, fmt)
        avail = fp is not None

        if method == "HEAD":
            return _head_resp(start_response, avail, fmt2, fp, rid, run_dir)

        # GET -> if available serve bytes, else keep 404 json
        if not avail:
            body = json.dumps({
                "ok": False,
                "http_code": 404,
                "error": "export_file_not_found",
                "rid": rid,
                "fmt": fmt2,
                "run_dir": str(run_dir),
            }, ensure_ascii=False).encode("utf-8")
            start_response("404 NOT FOUND", [("Content-Type","application/json; charset=utf-8"),
                                            ("Content-Length", str(len(body))),
                                            ("Cache-Control","no-store")])
            return [body]

        data = fp.read_bytes()
        if fmt2 == "html":
            ct = "text/html; charset=utf-8"
            cd = f'inline; filename={fp.name}'
        elif fmt2 == "zip":
            ct = "application/zip"
            cd = f'attachment; filename={fp.name}'
        else:
            ct = "application/pdf"
            cd = f'inline; filename={fp.name}'
        start_response("200 OK", [("Content-Type", ct),
                                 ("Content-Disposition", cd),
                                 ("Content-Length", str(len(data))),
                                 ("Cache-Control","no-store"),
                                 ("X-VSP-EXPORT-AVAILABLE","1"),
                                 ("X-VSP-EXPORT-FMT", fmt2)])
        return [data]

    return _wrapped
# === /VSP_WSGI_EXPORT_V3_HEADSHIM_V1 ===

try:
    _APP = globals().get("application") or globals().get("app")
    if _APP is not None:
        globals()["application"] = _vsp_wsgi_export_v3_headshim_v1(_APP)
except Exception:
    pass
'''

p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended export_v3 headshim v1")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"
echo "[DONE] restart 8910 to apply"
