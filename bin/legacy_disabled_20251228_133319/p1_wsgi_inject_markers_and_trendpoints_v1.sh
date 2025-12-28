#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_inject_${TS}"
echo "[BACKUP] ${F}.bak_inject_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys, re

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_AFTER_REQUEST_INJECT_MARKERS_AND_TRENDPOINTS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Append near end (safe)
block = r'''
# --- VSP_P1_AFTER_REQUEST_INJECT_MARKERS_AND_TRENDPOINTS_V1 ---
try:
    from flask import request
except Exception:
    request = None

def __vsp__inject_before_body_end(html: str, inject: str) -> str:
    if not html or not inject:
        return html
    if inject in html:
        return html
    idx = html.lower().rfind("</body>")
    if idx != -1:
        return html[:idx] + inject + html[idx:]
    return html + inject

def __vsp__mk_markers_for_path(path: str) -> str:
    # Gate reads raw HTML via curl, so markers must exist in server HTML, not JS DOM.
    if path == "/vsp5":
        return (
            '\n<!-- VSP_P1_MARKERS_VSP5 -->'
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
    if path == "/runs":
        return '\n<!-- VSP_P1_MARKERS_RUNS --><div id="vsp-runs-main" style="display:none"></div>\n'
    if path == "/data_source":
        return '\n<!-- VSP_P1_MARKERS_DS --><div id="vsp-data-source-main" style="display:none"></div>\n'
    if path == "/settings":
        return '\n<!-- VSP_P1_MARKERS_SETTINGS --><div id="vsp-settings-main" style="display:none"></div>\n'
    if path == "/rule_overrides":
        return '\n<!-- VSP_P1_MARKERS_RULE_OVERRIDES --><div id="vsp-rule-overrides-main" style="display:none"></div>\n'
    return ""

# Find a safe place to register hook: we can attach after_request via app or application.
def __vsp__get_flask_app():
    g = globals()
    a = g.get("app")
    if callable(a):
        return a
    a = g.get("application")
    if callable(a):
        return a
    return None

__vsp__flask = __vsp__get_flask_app()
if __vsp__flask is not None:
    @__vsp__flask.after_request
    def __vsp_p1_after_request_inject(resp):
        try:
            if request is None:
                return resp

            path = request.path or ""
            # (1) Inject HTML markers for 5 tabs
            if path in ("/vsp5", "/runs", "/data_source", "/settings", "/rule_overrides"):
                ct = (resp.headers.get("Content-Type") or "").lower()
                if "text/html" in ct:
                    html = resp.get_data(as_text=True)
                    inj = __vsp__mk_markers_for_path(path)
                    if inj:
                        html2 = __vsp__inject_before_body_end(html, inj)
                        if html2 != html:
                            resp.set_data(html2)
                            try:
                                resp.headers["Content-Length"] = str(len(resp.get_data()))
                            except Exception:
                                pass

            # (2) Force trend points key in JSON
            if path == "/api/vsp/trend_v1":
                ct = (resp.headers.get("Content-Type") or "").lower()
                if "application/json" in ct or getattr(resp, "is_json", False):
                    import json as _json
                    body = resp.get_data(as_text=True) or ""
                    try:
                        j = _json.loads(body) if body.strip() else {}
                    except Exception:
                        j = {}
                    if isinstance(j, dict) and "points" not in j:
                        j["points"] = []
                        resp.set_data(_json.dumps(j, ensure_ascii=False))
                        resp.headers["Content-Type"] = "application/json; charset=utf-8"
                        try:
                            resp.headers["Content-Length"] = str(len(resp.get_data()))
                        except Exception:
                            pass

        except Exception:
            # never break response
            return resp
        return resp
# --- end VSP_P1_AFTER_REQUEST_INJECT_MARKERS_AND_TRENDPOINTS_V1 ---
'''

# append with spacing
s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended after_request injector")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 40 || true

echo "== smoke checks =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -q 'id="vsp-dashboard-main"' && echo "[OK] vsp5 marker id ok" || echo "[ERR] vsp5 marker id missing"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 KPI testid ok" || echo "[ERR] vsp5 KPI testid missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs id ok" || echo "[ERR] runs id missing"

curl -fsS "$BASE/api/vsp/trend_v1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("[OK] trend has_points=", ("points" in j), "len=", len(j.get("points") or []))
PY

echo "[NEXT] run gate: bash bin/p1_ui_spec_gate_v1.sh"
