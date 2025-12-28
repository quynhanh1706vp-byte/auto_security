#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_add_gatestory_${TS}"
echo "[BACKUP] ${F}.bak_add_gatestory_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

SAFE_LINE = (
  r"bundle_tag = f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\n"
  r"<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={v}\"></script>\n"
  r"<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={v}\"></script>\n"
  r"<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>'"
)

# Replace the bundle_tag assignment (whatever it currently is) with SAFE_LINE
pat = re.compile(r'^(\s*)bundle_tag\s*=\s*.*$', re.M)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find bundle_tag assignment")

indent = m.group(1)
# only replace first occurrence to avoid touching other sections
s2 = pat.sub(indent + SAFE_LINE, s, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] bundle_tag rewritten with bundle + gate_story + containers_fix + luxe")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 includes 4 scripts =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 50
echo "[DONE] Ctrl+Shift+R /vsp5"
