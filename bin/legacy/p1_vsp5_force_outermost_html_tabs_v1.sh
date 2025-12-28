#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_FORCE_OUTERMOST_HTML_TABS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_force_vsp5_${TS}"
echo "[BACKUP] ${W}.bak_force_vsp5_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_FORCE_OUTERMOST_HTML_TABS_V1"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

block = textwrap.dedent(f"""
# ===================== {mark} =====================
# Outermost hard-override: ensure /vsp5 always includes Tabs+Topbar scripts (commercial contract).
def _vsp5_force_outermost_html_tabs_v1(app):
    def _mw(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if path == "/vsp5":
                import time
                asset_v = int(time.time())
                html = f\"\"\"<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>VSP • Dashboard</title>
<link rel="stylesheet" href="/static/css/vsp_dark_commercial_p1_2.css"/>
<link rel="stylesheet" href="/static/css/vsp_dash_only_v1.css?v={{asset_v}}"/>
</head>
<body class="vsp-body">
  <div class="topnav vsp5nav">
    <a class="brand" href="/vsp5">VSP</a>
    <a href="/vsp5">Dashboard</a>
    <a href="/runs">Runs &amp; Reports</a>
    <a href="/data_source">Data Source</a>
    <a href="/settings">Settings</a>
    <a href="/rule_overrides">Rule Overrides</a>
  </div>

  <div id="vsp5_root"></div>

  <!-- scripts: MUST be present for tabs5 contract -->
  <script src="/static/js/vsp_tabs4_autorid_v1.js?v={{asset_v}}"></script>
  <script src="/static/js/vsp_topbar_commercial_v1.js?v={{asset_v}}"></script>
  <!-- keep your existing dashboard logic -->
  <script src="/static/js/vsp_dashboard_luxe_v1.js?v={{asset_v}}"></script>
</body>
</html>\"\"\"
                body = html.encode("utf-8")
                headers = [
                    ("Content-Type", "text/html; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(body))),
                ]
                start_response("200 OK", headers)
                return [body]
        except Exception:
            pass
        return app(environ, start_response)
    return _mw

try:
    application = _vsp5_force_outermost_html_tabs_v1(application)
except Exception:
    pass
# ===================== /{mark} =====================
""").rstrip() + "\n"

s2 = s.rstrip() + "\n\n" + block
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] forced outermost /vsp5 html with tabs/topbar."
