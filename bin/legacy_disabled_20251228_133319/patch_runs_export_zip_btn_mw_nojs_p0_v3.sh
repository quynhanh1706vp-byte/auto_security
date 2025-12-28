#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_exportbtn_nojs_${TS}"
echo "[BACKUP] ${F}.bak_runs_exportbtn_nojs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_EXPORT_ZIP_NOJS_MW_P0_V3"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

snippet = r'''
# === VSP_RUNS_EXPORT_ZIP_NOJS_MW_P0_V3 ===
class VSPRunsExportZipNoJSMWP0V3:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path != "/runs":
            return self.app(environ, start_response)

        meta = {}
        def sr(status, headers, exc_info=None):
            meta["status"] = status
            meta["headers"] = headers
            meta["exc_info"] = exc_info
            return lambda _x: None

        app_iter = self.app(environ, sr)

        body = b""
        try:
            for chunk in app_iter:
                if chunk:
                    body += chunk
        finally:
            try:
                close = getattr(app_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = meta.get("headers") or []
        ct = ""
        for k,v in headers:
            if str(k).lower() == "content-type":
                ct = str(v); break

        if ("text/html" in ct) and (b"/api/vsp/run_file" in body) and (MARK.encode() not in body):
            try:
                html = body.decode("utf-8", "replace")
            except Exception:
                html = str(body)

            # Insert NO-JS Export button after any run_file link (per anchor)
            # Capture run_id from query string.
            runfile_a_pat = re.compile(
                r'(<a\b[^>]*href="[^"]*/api/vsp/run_file\?[^"]*?\brun_id=([^"&]+)[^"]*"[^>]*>.*?</a>)',
                re.IGNORECASE | re.DOTALL
            )

            def add_btn(m):
                a = m.group(1)
                rid = m.group(2)
                # Avoid duplicating if already inserted
                if "data-vsp-export-zip" in a:
                    return a
                btn = (
                    ' <a data-vsp-export-zip="1" '
                    'href="/api/vsp/export_zip?run_id=' + rid + '" '
                    'style="margin-left:8px;text-decoration:none;display:inline-block;'
                    'padding:7px 10px;border-radius:10px;font-weight:800;'
                    'border:1px solid rgba(90,140,255,.35);background:rgba(90,140,255,.16);color:inherit;">'
                    'Export ZIP</a>'
                )
                return a + btn

            html2, n = runfile_a_pat.subn(add_btn, html)
            if n > 0:
                # Add a marker comment that won't be stripped like <script>
                marker = "\n<!-- " + MARK + " injected=" + str(n) + " -->\n"
                if "</body>" in html2:
                    html2 = html2.replace("</body>", marker + "</body>", 1)
                else:
                    html2 = html2 + marker

                body = html2.encode("utf-8", "replace")

        # fix Content-Length
        new_headers=[]
        for k,v in headers:
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k,v))
        new_headers.append(("Content-Length", str(len(body))))

        start_response(meta.get("status","200 OK"), new_headers, meta.get("exc_info"))
        return [body]

try:
    if "application" in globals():
        _a = globals().get("application")
        if _a is not None and not getattr(_a, "__VSP_RUNS_EXPORT_ZIP_NOJS_MW_P0_V3__", False):
            _mw = VSPRunsExportZipNoJSMWP0V3(_a)
            setattr(_mw, "__VSP_RUNS_EXPORT_ZIP_NOJS_MW_P0_V3__", True)
            globals()["application"] = _mw
except Exception:
    pass
# === /VSP_RUNS_EXPORT_ZIP_NOJS_MW_P0_V3 ===
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] appended NO-JS MW injector V3")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
