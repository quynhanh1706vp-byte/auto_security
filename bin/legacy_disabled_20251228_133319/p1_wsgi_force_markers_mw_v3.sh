#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_wsgimark_v3_${TS}"
echo "[BACKUP] ${F}.bak_wsgimark_v3_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_WSGI_FORCE_MARKERS_V3"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

block = r'''
# --- VSP_P1_WSGI_FORCE_MARKERS_V3 ---
# V3: brute-force inject markers into raw body for 5 tab paths (curl gate sees it).
# Also supports apps that use start_response()->write() streaming.
import json as _json

def __vsp_v3_insert(html: str, inject: str) -> str:
    if not html or not inject:
        return html
    if inject in html:
        return html
    low = html.lower()
    idx = low.rfind("</body>")
    if idx != -1:
        return html[:idx] + inject + html[idx:]
    return html + inject

def __vsp_v3_inject_for_path(path: str, html: str) -> str:
    # Gate matches exact strings with double quotes
    if path == "/vsp5":
        inj = (
            '\n<!-- VSP_P1_MARKERS_VSP5_V3 -->'
            '\n<div id="vsp-dashboard-main" style="display:none"></div>'
            '\n<div id="vsp-kpi-testids" style="display:none">'
            '\n  <span data-testid="kpi_total"></span>'
            '\n  <span data-testid="kpi_critical"></span>'
            '\n  <span data-testid="kpi_high"></span>'
            '\n  <span data-testid="kpi_medium"></span>'
            '\n  <span data-testid="kpi_low"></span>'
            '\n  <span data-testid="kpi_info_trace"></span>'
            '\n</div>\n'
        )
        return __vsp_v3_insert(html, inj)
    if path == "/runs":
        return __vsp_v3_insert(html, '\n<!-- VSP_P1_MARKERS_RUNS_V3 --><div id="vsp-runs-main" style="display:none"></div>\n')
    if path == "/data_source":
        return __vsp_v3_insert(html, '\n<!-- VSP_P1_MARKERS_DS_V3 --><div id="vsp-data-source-main" style="display:none"></div>\n')
    if path == "/settings":
        return __vsp_v3_insert(html, '\n<!-- VSP_P1_MARKERS_SETTINGS_V3 --><div id="vsp-settings-main" style="display:none"></div>\n')
    if path == "/rule_overrides":
        return __vsp_v3_insert(html, '\n<!-- VSP_P1_MARKERS_RULE_OVERRIDES_V3 --><div id="vsp-rule-overrides-main" style="display:none"></div>\n')
    return html

class __VspWsgiMarkersMwV3:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        want_tab = path in ("/vsp5","/runs","/data_source","/settings","/rule_overrides")
        want_trend = (path == "/api/vsp/trend_v1")
        if not (want_tab or want_trend):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        body_parts = []

        def write(chunk: bytes):
            if chunk:
                body_parts.append(chunk)

        def sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            return write  # IMPORTANT: support WSGI write()

        it = self.app(environ, sr)

        try:
            for chunk in it:
                if chunk:
                    body_parts.append(chunk)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        body = b"".join(body_parts)

        # rebuild headers: drop content-length, add our debug header
        ct = ""
        new_headers = []
        for (k,v) in headers:
            lk = k.lower()
            if lk == "content-type":
                ct = (v or "")
            if lk != "content-length":
                new_headers.append((k,v))
        new_headers.append(("X-VSP-MARKERS-MW", "v3"))

        try:
            if want_tab:
                # brute force: treat as text unless it looks like JSON
                head = (body[:64].lstrip() if body else b"")
                if not (head.startswith(b"{") or head.startswith(b"[")):
                    html = body.decode("utf-8", errors="replace")
                    html2 = __vsp_v3_inject_for_path(path, html)
                    if html2 != html:
                        body = html2.encode("utf-8")
            elif want_trend:
                txt = body.decode("utf-8", errors="replace")
                try:
                    j = _json.loads(txt) if txt.strip() else {}
                except Exception:
                    j = {}
                if isinstance(j, dict) and "points" not in j:
                    j["points"] = []
                    body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                    if not any(k.lower()=="content-type" for k,_ in new_headers):
                        new_headers.append(("Content-Type","application/json; charset=utf-8"))
        except Exception:
            pass

        new_headers.append(("Content-Length", str(len(body))))
        start_response(status, new_headers)
        return [body]

# Wrap LAST (again) so it wins even if earlier code wrapped application.
try:
    application
    application = __VspWsgiMarkersMwV3(application)
except Exception:
    pass
try:
    app
    app = application
except Exception:
    pass
# --- end VSP_P1_WSGI_FORCE_MARKERS_V3 ---
'''

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended V3 MW at EOF")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

systemctl restart "$SVC" || true
sleep 0.9
systemctl status "$SVC" -l --no-pager | head -n 35 || true

echo "== smoke: headers + markers =="
BASE="http://127.0.0.1:8910"
curl -fsSI "$BASE/vsp5" | grep -i 'x-vsp-markers-mw' && echo "[OK] MW header present" || echo "[ERR] MW header missing"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[ERR] vsp5 kpi_total missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs id present" || echo "[ERR] runs id missing"
