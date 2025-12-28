#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_vsp5_dashcommercial_${TS}"
echo "[BACKUP] ${F}.bak_vsp5_dashcommercial_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

marker = "VSP_P1_VSP5_SWITCH_TO_DASHCOMMERCIAL_V1_FIX_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# 1) Ensure /vsp5 HTML uses correct mount id (so DashCommercialV1 renders into it)
s, n_root = re.subn(r'id="vsp5_root"', 'id="vsp_dashboard_mount_v1"', s)

# 2) Replace SAFE MODE GateStory include comment (if present)
s = s.replace(
    "<!-- SAFE MODE: only Gate Story script (NO legacy dash) -->",
    f"<!-- {marker}: DASH MODE: DashCommercialV1 (single renderer) -->"
)

# 3) Replace GateStory script include with DashCommercialV1 (keep ?v=... intact)
#    This is the key: /vsp5 must include vsp_dashboard_commercial_v1.js
s, n_js = re.subn(
    r'(/static/js/)vsp_dashboard_gate_story_v1\.js(\?v=[0-9]+)',
    r'\1vsp_dashboard_commercial_v1.js\2',
    s
)

# 4) Ensure meta vsp-page=dashboard exists somewhere in <head> of vsp5 template (best-effort)
if ('name="vsp-page"' not in s) and ("name='vsp-page'" not in s):
    s, n_head = re.subn(
        r'(<meta\s+name="viewport"[^>]*>\s*)',
        r'\1  <meta name="vsp-page" content="dashboard"/>\n',
        s,
        count=1,
        flags=re.I
    )
else:
    n_head = 0

if s == orig:
    raise SystemExit("[ERR] No changes applied. Pattern not found (route template differs).")

p.write_text(s, encoding="utf-8")
print(f"[OK] patched {p}")
print(f"  - replaced vsp5_root id: {n_root}")
print(f"  - replaced gate story js -> dashcommercial js: {n_js}")
print(f"  - inserted meta vsp-page: {n_head}")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo
echo "[DONE] /vsp5 now should load DashCommercialV1."
echo "Next:"
echo "  1) restart UI service"
echo "  2) HARD refresh /vsp5 (Ctrl+Shift+R)"
echo "  3) verify HTML includes dashcommercial:"
echo '     curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE "dashcommercial|gate_story" || true'
