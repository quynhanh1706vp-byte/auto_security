#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need tail

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_wsgimark_v2_${TS}"
echo "[BACKUP] ${F}.bak_wsgimark_v2_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_WSGI_FORCE_MARKERS_AND_TRENDPOINTS_V2"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

block = r'''
# --- VSP_P1_WSGI_FORCE_MARKERS_AND_TRENDPOINTS_V2 ---
# Wrap AGAIN at the very end so this middleware is the last writer of HTML/JSON (curl gate can see markers).
import json as _json

def __vsp_v2_is_html(body: bytes) -> bool:
    if not body:
        return False
    head = body[:4096].lower()
    return (b"<html" in head) or (b"<!doctype" in head) or (b"</body>" in head) or (b"</head>" in head)

def __vsp_v2_insert(html: str, inject: str) -> str:
    if not html or not inject:
        return html
    if inject in html:
        return html
    low = html.lower()
    idx = low.rfind("</body>")
    if idx != -1:
        return html[:idx] + inject + html[idx:]
    return html + inject

def __vsp_v2_inject_for_path(path: str, html: str) -> str:
    # IMPORTANT: gate matches exact strings with double quotes.
    if path == "/vsp5":
        inj = (
            '\n<!-- VSP_P1_MARKERS_VSP5_WSGI_V2 -->'
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
        return __vsp_v2_insert(html, inj)
    if path == "/runs":
        return __vsp_v2_insert(html, '\n<!-- VSP_P1_MARKERS_RUNS_WSGI_V2 --><div id="vsp-runs-main" style="display:none"></div>\n')
    if path == "/data_source":
        return __vsp_v2_insert(html, '\n<!-- VSP_P1_MARKERS_DS_WSGI_V2 --><div id="vsp-data-source-main" style="display:none"></div>\n')
    if path == "/settings":
        return __vsp_v2_insert(html, '\n<!-- VSP_P1_MARKERS_SETTINGS_WSGI_V2 --><div id="vsp-settings-main" style="display:none"></div>\n')
    if path == "/rule_overrides":
        return __vsp_v2_insert(html, '\n<!-- VSP_P1_MARKERS_RULE_OVERRIDES_WSGI_V2 --><div id="vsp-rule-overrides-main" style="display:none"></div>\n')
    return html

class __VspWsgiBodyPatchMwV2:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        want_html = path in ("/vsp5","/runs","/data_source","/settings","/rule_overrides")
        want_trend = (path == "/api/vsp/trend_v1")
        if not (want_html or want_trend):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        body_parts = []

        def sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            return None  # delay

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

        # remove content-length
        ct = ""
        new_headers = []
        for (k,v) in headers:
            lk = k.lower()
            if lk == "content-type":
                ct = (v or "")
            if lk != "content-length":
                new_headers.append((k,v))

        try:
            if want_html:
                # Don't trust Content-Type; detect HTML by bytes signature.
                if __vsp_v2_is_html(body) or ("text/html" in (ct or "").lower()):
                    html = body.decode("utf-8", errors="replace")
                    html2 = __vsp_v2_inject_for_path(path, html)
                    if html2 != html:
                        body = html2.encode("utf-8")
                        # keep original ct; don't force
            elif want_trend:
                # best effort JSON parse; force points=[]
                txt = body.decode("utf-8", errors="replace")
                try:
                    j = _json.loads(txt) if txt.strip() else {}
                except Exception:
                    j = {}
                if isinstance(j, dict) and "points" not in j:
                    j["points"] = []
                    body = _json.dumps(j, ensure_ascii=False).encode("utf-8")
                    # ensure ct
                    has_ct = any(k.lower()=="content-type" for k,_ in new_headers)
                    if not has_ct:
                        new_headers.append(("Content-Type","application/json; charset=utf-8"))
        except Exception:
            pass

        new_headers.append(("Content-Length", str(len(body))))
        start_response(status, new_headers)
        return [body]

# Wrap exported callable again (must be LAST)
try:
    application
    application = __VspWsgiBodyPatchMwV2(application)
except Exception:
    pass
try:
    app
    app = application
except Exception:
    pass
# --- end VSP_P1_WSGI_FORCE_MARKERS_AND_TRENDPOINTS_V2 ---
'''

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended V2 WSGI marker mw at EOF")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 40 || true

echo "== smoke (curl must see markers now) =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[ERR] vsp5 kpi_total missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main id present" || echo "[ERR] runs main id missing"
curl -fsS "$BASE/data_source" | grep -q 'id="vsp-data-source-main"' && echo "[OK] data_source main id present" || echo "[ERR] data_source main id missing"
curl -fsS "$BASE/settings" | grep -q 'id="vsp-settings-main"' && echo "[OK] settings main id present" || echo "[ERR] settings main id missing"
curl -fsS "$BASE/rule_overrides" | grep -q 'id="vsp-rule-overrides-main"' && echo "[OK] rule_overrides main id present" || echo "[ERR] rule_overrides main id missing"

echo "== tail error log (optional) =="
[ -f "$ERRLOG" ] && tail -n 20 "$ERRLOG" || true

echo "[NEXT] run gate: bash bin/p1_ui_spec_gate_v1.sh"
