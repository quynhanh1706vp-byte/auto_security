#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_tabs4_mw_v2_${TS}"
echo "[BACKUP] ${W}.bak_tabs4_mw_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_TABS4_WSGI_MW_INJECT_V2"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_TABS4_WSGI_MW_INJECT_V2 =====================
# WSGI middleware inject for 4 tabs only (NO dashboard /vsp5, NO /reports).
def _vsp_tabs4_mw_inject_v2(app):
    import re, time
    targets = {"/runs", "/runs_reports", "/settings", "/data_source", "/rule_overrides"}

    def _sanitize(html: str, v: str) -> str:
        # sanitize ?v={{...}}
        try:
            html = re.sub(r'vsp_tabs4_autorid_v1\.js\?v=\{\{[^}]*\}\}', "vsp_tabs4_autorid_v1.js?v="+v, html)
        except Exception:
            pass
        # sanitize ?v={... (truncated/bad)
        try:
            html = re.sub(r'vsp_tabs4_autorid_v1\.js\?v=\{[^\s">]*', "vsp_tabs4_autorid_v1.js?v="+v, html)
        except Exception:
            pass
        return html

    def _inject(html: str, v: str) -> str:
        tag = '\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v='+v+'"></script>\n'
        if "vsp_tabs4_autorid_v1.js" in html:
            return html
        if "</head>" in html:
            return html.replace("</head>", tag + "</head>", 1)
        if "</body>" in html:
            return html.replace("</body>", tag + "</body>", 1)
        return html + tag

    def middleware(environ, start_response):
        path = (environ.get("PATH_INFO") or "").rstrip("/") or "/"

        # exclude dashboard + reports
        if path.startswith("/vsp5") or path == "/reports":
            return app(environ, start_response)

        if path not in targets:
            return app(environ, start_response)

        captured = {"status": None, "headers": None}

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers) if headers else []
            # delay calling start_response (we may rewrite)
            return lambda x: None

        resp_iter = app(environ, _sr)

        headers = captured["headers"] or []
        ct = ""
        for k, v in headers:
            if (k or "").lower() == "content-type":
                ct = (v or "").lower()
                break
        if "text/html" not in ct:
            # pass-through: must call real start_response
            start_response(captured["status"] or "200 OK", headers)
            return resp_iter

        # buffer body
        try:
            body_bytes = b"".join(resp_iter)
        finally:
            try:
                close = getattr(resp_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        try:
            html = body_bytes.decode("utf-8", errors="replace")
        except Exception:
            start_response(captured["status"] or "200 OK", headers)
            return [body_bytes]

        v = str(int(time.time()))
        html2 = _sanitize(html, v)
        html2 = _inject(html2, v)
        out = html2.encode("utf-8", errors="replace")

        # rewrite headers
        new_headers = []
        for k, vv in headers:
            lk = (k or "").lower()
            if lk in ("content-length",):
                continue
            new_headers.append((k, vv))
        new_headers.append(("Content-Length", str(len(out))))
        new_headers.append(("Cache-Control", "no-store"))
        new_headers.append(("X-VSP-AUTORID-INJECT", "MW2"))

        start_response(captured["status"] or "200 OK", new_headers)
        return [out]

    return middleware

# Wrap WSGI callable(s) if present
try:
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_tabs4_mw_inject_v2(application)
except Exception:
    pass
try:
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_tabs4_mw_inject_v2(app)
except Exception:
    pass
# ===================== /VSP_P1_TABS4_WSGI_MW_INJECT_V2 =====================
""").strip() + "\n"

W.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + compiled:", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify tabs4 (must show header + src) =="
for p in /runs /runs_reports /settings /data_source /rule_overrides; do
  echo "-- $p --"
  curl -sS -I "$BASE$p" | grep -i "X-VSP-AUTORID-INJECT" || echo "[WARN] header missing"
  curl -sS "$BASE$p" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 1 || echo "[WARN] src missing"
done
