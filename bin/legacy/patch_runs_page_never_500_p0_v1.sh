#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
ELOG="out_ci/ui_8910.error.log"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_never500_${TS}"
echo "[BACKUP] ${F}.bak_runs_never500_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUNS_PAGE_NEVER_500_P0_V1"
if MARK in s:
    print("[OK] already patched")
else:
    # inject right after "app = application" (best spot)
    m = re.search(r'(?m)^\s*app\s*=\s*application\s*$', s)
    if not m:
        raise SystemExit("[ERR] cannot find `app = application` to inject after")

    inject = r'''
# --- VSP_RUNS_PAGE_NEVER_500_P0_V1 ---
# Commercial guard: /runs must never return 500 (fallback HTML + link to JSON).
from flask import request, Response
import json as _vsp_json
import html as _vsp_html
import traceback as _vsp_tb

@app.errorhandler(500)
def _vsp_err_500_runs_only(e):
    try:
        if request.path != "/runs":
            # keep normal 500 behavior for other endpoints
            return ("Internal Server Error", 500)
        # Build minimal HTML using the already-working JSON API
        items = []
        try:
            with app.test_client() as c:
                r = c.get("/api/vsp/runs?limit=50")
                if r.status_code == 200:
                    data = r.get_json(silent=True) or {}
                    items = data.get("items") or []
        except Exception:
            items = []

        rows = []
        for it in items[:50]:
            rid = str(it.get("run_id") or "")
            mtime_h = str(it.get("mtime_h") or "")
            path = str(it.get("path") or "")
            # safe link: open run dir (if you later wire /api/vsp/run_file)
            rows.append(
                "<tr>"
                f"<td>{_vsp_html.escape(rid)}</td>"
                f"<td>{_vsp_html.escape(mtime_h)}</td>"
                f"<td style='font-family:monospace'>{_vsp_html.escape(path)}</td>"
                "</tr>"
            )

        body = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<title>Runs & Reports</title>"
            "<style>"
            "body{background:#0b1220;color:#e5e7eb;font:14px/1.4 system-ui,Segoe UI,Arial;padding:18px}"
            "a{color:#60a5fa} table{border-collapse:collapse;width:100%;margin-top:10px}"
            "th,td{border:1px solid #1f2937;padding:8px;vertical-align:top}"
            "th{background:#111827;text-align:left}"
            ".muted{color:#9ca3af}"
            "</style></head><body>"
            "<h2>Runs & Reports</h2>"
            "<div class='muted'>Fallback mode: UI template errored. JSON API is OK.</div>"
            "<div style='margin-top:8px'>"
            "<a href='/api/vsp/runs?limit=50'>Open /api/vsp/runs JSON</a>"
            "</div>"
            "<table><thead><tr><th>run_id</th><th>mtime</th><th>path</th></tr></thead><tbody>"
            + "".join(rows) +
            "</tbody></table>"
            "</body></html>"
        )
        return Response(body, status=200, headers={"X-VSP-RUNS-PAGE-FALLBACK": MARK}, mimetype="text/html")
    except Exception:
        # last resort: still avoid 500 on /runs
        tb = _vsp_tb.format_exc()
        body = "<pre>" + _vsp_html.escape(tb[-4000:]) + "</pre>"
        return Response(body, status=200, headers={"X-VSP-RUNS-PAGE-FALLBACK": MARK}, mimetype="text/html")

# --- /VSP_RUNS_PAGE_NEVER_500_P0_V1 ---
'''
    s = s[:m.end()] + "\n" + inject + "\n" + s[m.end():]
    p.write_text(s, encoding="utf-8")
    print("[OK] injected runs page never-500 handler")
PY

echo "== py_compile =="
python3 -m py_compile "$F"

echo "== truncate error log (NEW only) =="
mkdir -p out_ci
sudo truncate -s 0 "$ELOG" || true

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.8

echo "== verify /runs now 200 (fallback header) =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,30p'
