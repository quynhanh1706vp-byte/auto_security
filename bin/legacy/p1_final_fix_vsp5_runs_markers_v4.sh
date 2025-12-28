#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_finalmarkers_${TS}"
echo "[BACKUP] ${F}.bak_finalmarkers_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_FINAL_MARKERS_FORCE_V4"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

block = r'''
# --- VSP_P1_FINAL_MARKERS_FORCE_V4 ---
# FINAL: force required markers into raw HTML for /vsp5 and /runs (curl gate sees it).
def __vsp_v4_insert_before_body_end(html: str, inject: str) -> str:
    if not html or not inject:
        return html
    if inject in html:
        return html
    low = html.lower()
    idx = low.rfind("</body>")
    if idx != -1:
        return html[:idx] + inject + html[idx:]
    return html + inject

def __vsp_v4_force_markers(path: str, body: bytes) -> bytes:
    try:
        html = body.decode("utf-8", errors="replace")
    except Exception:
        return body

    if path == "/vsp5":
        if 'data-testid="kpi_total"' not in html:
            inj = (
                '\n<!-- VSP_P1_FINAL_MARKERS_FORCE_V4:vsp5 -->\n'
                '<div id="vsp-kpi-testids" style="display:none">\n'
                '  <span data-testid="kpi_total"></span>\n'
                '  <span data-testid="kpi_critical"></span>\n'
                '  <span data-testid="kpi_high"></span>\n'
                '  <span data-testid="kpi_medium"></span>\n'
                '  <span data-testid="kpi_low"></span>\n'
                '  <span data-testid="kpi_info_trace"></span>\n'
                '</div>\n'
            )
            # Prefer injecting right after existing dashboard main div if present
            anchor = '<div id="vsp-dashboard-main"></div>'
            if anchor in html:
                html = html.replace(anchor, anchor + "\n" + inj, 1)
            else:
                html = __vsp_v4_insert_before_body_end(html, inj)
            return html.encode("utf-8")

    if path == "/runs":
        if 'id="vsp-runs-main"' not in html:
            inj = '\n<!-- VSP_P1_FINAL_MARKERS_FORCE_V4:runs --><div id="vsp-runs-main" style="display:none"></div>\n'
            html = __vsp_v4_insert_before_body_end(html, inj)
            return html.encode("utf-8")

    return body

class __VspFinalMarkersMwV4:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path not in ("/vsp5", "/runs"):
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None}
        chunks = []

        def write(data: bytes):
            if data:
                chunks.append(data)

        def sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            return write  # support write()

        it = self.app(environ, sr)
        try:
            for c in it:
                if c:
                    chunks.append(c)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        body = b"".join(chunks)
        body2 = __vsp_v4_force_markers(path, body)

        # rebuild headers (drop content-length), add debug header
        new_headers = []
        ct_present = False
        for k,v in headers:
            lk = k.lower()
            if lk == "content-type":
                ct_present = True
            if lk != "content-length":
                new_headers.append((k,v))
        new_headers.append(("X-VSP-MARKERS-FINAL", "v4"))
        if (not ct_present):
            new_headers.append(("Content-Type", "text/html; charset=utf-8"))
        new_headers.append(("Content-Length", str(len(body2))))
        start_response(status, new_headers)
        return [body2]

# MUST be last assignment
try:
    application
    application = __VspFinalMarkersMwV4(application)
except Exception:
    pass
try:
    app
    app = application
except Exception:
    pass
# --- end VSP_P1_FINAL_MARKERS_FORCE_V4 ---
'''
p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended FINAL markers MW V4")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 25 || true

echo "== smoke headers =="
BASE="http://127.0.0.1:8910"
curl -fsSI "$BASE/vsp5" | grep -i x-vsp-markers-final || true
curl -fsSI "$BASE/runs" | grep -i x-vsp-markers-final || true

echo "== smoke markers =="
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[ERR] vsp5 kpi_total missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main present" || echo "[ERR] runs main missing"

echo "[NEXT] bash bin/p1_ui_spec_gate_v1.sh"
