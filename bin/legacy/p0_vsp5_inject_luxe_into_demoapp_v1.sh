#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
JS="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS (run p0_dashboard_luxe_v1.sh first)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_luxe_inject_${TS}"
echo "[BACKUP] ${APP}.bak_luxe_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
ts = str(int(time.time()))

# 1) add host div before vsp5_root if vsp5_root exists
if 'id="vsp5_root"' in s and 'id="vsp_luxe_host"' not in s:
    s2, n = re.subn(r'(<div\s+id="vsp5_root"\s*>\s*</div>)',
                    r'<div id="vsp_luxe_host"></div>\n  \1', s, count=1)
    if n:
        s = s2

# 2) inject luxe script right after any bundle commercial include in the HTML string
if "vsp_dashboard_luxe_v1.js" not in s:
    s2, n = re.subn(
        r'(<script\s+src="\/static\/js\/vsp_bundle_commercial_v2\.js[^"]*"\s*>\s*<\/script>)',
        r'\1\n<script src="/static/js/vsp_dashboard_luxe_v1.js?v=%s"></script>' % ts,
        s,
        count=1
    )
    if n == 0:
        raise SystemExit("[ERR] cannot find vsp_bundle_commercial_v2.js script tag in vsp_demo_app.py to inject")
    s = s2

p.write_text(s, encoding="utf-8")
print("[OK] injected luxe into vsp_demo_app.py")
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3
echo "[DONE] Ctrl+Shift+R reload /vsp5"
