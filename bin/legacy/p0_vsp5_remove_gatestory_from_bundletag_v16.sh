#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_v16_${TS}"
echo "[BACKUP] ${WSGI}.bak_v16_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_VSP5_BUNDLETAG_CANON_V15"
if marker not in s:
    raise SystemExit("[ERR] marker not found: VSP_P0_VSP5_BUNDLETAG_CANON_V15 (run v15 first)")

# Replace the whole bundle_tag block to EXCLUDE gate_story
pat = re.compile(
    r'(?ms)^\s*#\s*VSP_P0_VSP5_BUNDLETAG_CANON_V15\s*\n\s*bundle_tag\s*=\s*\(\s*.*?\)\s*\n'
)

def repl(m):
    indent = re.match(r'^(\s*)#', m.group(0)).group(1)
    return (
        f"{indent}# VSP_P0_VSP5_BUNDLETAG_CANON_V16\n"
        f"{indent}bundle_tag = (\n"
        f"{indent}    f'<script src=\"/static/js/vsp_p0_fetch_shim_v1.js?v={{v}}\"></script>'\n"
        f"{indent}    f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={{v}}\"></script>'\n"
        f"{indent}    f'<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={{v}}\"></script>'\n"
        f"{indent}    f'<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={{v}}\"></script>'\n"
        f"{indent})\n"
    )

s2, n = pat.subn(repl, s, count=1)
if n != 1:
    raise SystemExit(f"[ERR] bundle_tag block replace failed (n={n})")

p.write_text(s2, encoding="utf-8")
print("[OK] rewrote bundle_tag => V16 (removed gate_story from bundle_tag)")
PY

echo "== py_compile WSGI =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || { echo "[ERR] restart failed"; systemctl status "$SVC" --no-pager || true; exit 2; }

echo "== smoke /vsp5 script tags =="
html="$(curl -fsS "$BASE/vsp5")"
echo "$html" | egrep -n "vsp_p0_fetch_shim_v1|vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 120 || true

echo "== count gate_story occurrences =="
echo "$html" | grep -o "vsp_dashboard_gate_story_v1.js" | wc -l | awk '{print "gate_story_count=" $1}'

echo
echo "[DONE] Ctrl+Shift+R /vsp5"
