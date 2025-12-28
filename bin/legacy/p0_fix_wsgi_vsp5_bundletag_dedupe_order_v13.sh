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
cp -f "$F" "${F}.bak_bundletag_dedupe_${TS}"
echo "[BACKUP] ${F}.bak_bundletag_dedupe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_VSP5_BUNDLE_TAG_DEDUPE_ORDER_V13"
if marker in s:
    print("[SKIP] already patched:", marker)
    sys.exit(0)

# replace ANY bundle_tag assignment that contains vsp_bundle_commercial_v2.js
# including multiline triple-quote or broken multiline single quote
pat = re.compile(r"""
bundle_tag\s*=\s*          # lhs
(?:f)?                     # optional f
(?:                         # rhs: triple or single/double
  \"\"\"[\s\S]*?\"\"\" |
  \'\'\'[\s\S]*?\'\'\' |
  \"[\s\S]*?\" |
  \'[\s\S]*?\'
)
""", re.VERBOSE)

m = pat.search(s)
if not m:
    print("[ERR] cannot locate bundle_tag assignment")
    sys.exit(2)

chunk = m.group(0)
if "vsp_bundle_commercial_v2.js" not in chunk:
    # try find a more specific one
    m2 = re.search(r"bundle_tag\s*=\s*[\s\S]{0,600}?vsp_bundle_commercial_v2\.js[\s\S]{0,600}", s)
    if not m2:
        print("[ERR] cannot locate bundle_tag containing vsp_bundle_commercial_v2.js")
        sys.exit(3)

replacement = (
    f"# ===================== {marker} =====================\n"
    "bundle_tag = ''.join([\n"
    "  f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>',\n"
    "  f'<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={v}\"></script>',\n"
    "  f'<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={v}\"></script>',\n"
    "  f'<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>',\n"
    "])\n"
    f"# ===================== /{marker} =====================\n"
)

s2, n = pat.subn(replacement, s, count=1)
if n != 1:
    print("[ERR] replacement failed; n=", n)
    sys.exit(4)

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched bundle_tag (dedupe + safe join) and py_compile OK")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 includes scripts (should be exactly 4 lines, no duplicates) =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 20
echo "[DONE] Ctrl+Shift+R /vsp5"
