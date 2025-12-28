#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl; need sed; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_vsp5_safe_v2_${TS}"
echo "[BACKUP] ${F}.bak_vsp5_safe_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_WSGI_VSP5_SAFE_MODE_GATE_STORY_ONLY_V2"

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# detect flask app var name (x = Flask(...))
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] flask app var:", appv)

# Hard remove previous SAFE_MODE blocks if any (optional)
for old in [
    "VSP_P1_VSP5_SAFE_MODE_GATE_STORY_ONLY_V1",
    "VSP_P1_VSP5_SAFE_MODE_GATE_STORY_ONLY_V1_FIXED",
]:
    s, n = re.subn(rf"\n?# --- {re.escape(old)} ---.*?# --- /{re.escape(old)} ---\n?", "\n", s, flags=re.S)
    if n:
        print("[OK] removed old block:", old)

block = f"""
# --- {MARK} ---
def _vsp_p1_wsgi_vsp5_safe_mode_gate_story_only_v2(wsgi_app):
    import time

    def _app(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()

            if path != "/vsp5":
                return wsgi_app(environ, start_response)

            asset_v = str(int(time.time()))
            html_lines = [
                "<!doctype html>",
                "<html lang=\\"en\\">",
                "<head>",
                "  <meta charset=\\"utf-8\\"/>",
                "  <meta name=\\"viewport\\" content=\\"width=device-width, initial-scale=1\\"/>",
                "  <meta http-equiv=\\"Cache-Control\\" content=\\"no-cache, no-store, must-revalidate\\"/>",
                "  <meta http-equiv=\\"Pragma\\" content=\\"no-cache\\"/>",
                "  <meta http-equiv=\\"Expires\\" content=\\"0\\"/>",
                "  <title>VSP5</title>",
                "  <style>",
                "    body{{ margin:0; background:#0b1220; color:rgba(226,232,240,.96);",
                "          font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; }}",
                "    .vsp5nav{{ display:flex; gap:10px; padding:10px 14px; border-bottom:1px solid rgba(255,255,255,.10);",
                "              background: rgba(0,0,0,.22); position:sticky; top:0; z-index:9999; }}",
                "    .vsp5nav a{{ color:rgba(226,232,240,.92); text-decoration:none; font-size:12px;",
                "                padding:8px 10px; border:1px solid rgba(255,255,255,.14); border-radius:12px; }}",
                "    .vsp5nav a:hover{{ background: rgba(255,255,255,.06); }}",
                "    #vsp5_root{{ min-height: 60vh; }}",
                "  </style>",
                "</head>",
                "<body>",
                "  <div class=\\"vsp5nav\\">",
                "    <a href=\\"/vsp5\\">Dashboard</a>",
                "    <a href=\\"/runs\\">Runs &amp; Reports</a>",
                "    <a href=\\"/data_source\\">Data Source</a>",
                "    <a href=\\"/settings\\">Settings</a>",
                "    <a href=\\"/rule_overrides\\">Rule Overrides</a>",
                "  </div>",
                "  <div id=\\"vsp5_root\\"></div>",
                "",
                "  <!-- SAFE MODE: only Gate Story script (NO legacy dash) -->",
                "  <script src=\\"/static/js/vsp_dashboard_gate_story_v1.js?v=" + asset_v + "\\"></script>",
                "</body>",
                "</html>",
            ]
            html = "\\n".join(html_lines).encode("utf-8", errors="ignore")
            headers = [
                ("Content-Type", "text/html; charset=utf-8"),
                ("Cache-Control", "no-cache, no-store, must-revalidate"),
                ("Pragma", "no-cache"),
                ("Expires", "0"),
                ("Content-Length", str(len(html))),
            ]
            start_response("200 OK", headers)
            if method == "HEAD":
                return [b""]
            return [html]
        except Exception:
            return wsgi_app(environ, start_response)

    return _app

try:
    {appv}.wsgi_app = _vsp_p1_wsgi_vsp5_safe_mode_gate_story_only_v2({appv}.wsgi_app)
except Exception:
    pass
# --- /{MARK} ---
"""

s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart clean :8910 =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE /vsp5 must ONLY include gate_story script =="
curl -fsS "$BASE/vsp5" | grep -n "<script src=" | head -n 10 || true
echo "== PROBE legacy dash must be absent =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_topbar\|vsp_dashboard_kpi\|vsp_bundle\|Chart/container" | head -n 10 || true
echo "[DONE] VSP5 SAFE MODE V2 applied."
