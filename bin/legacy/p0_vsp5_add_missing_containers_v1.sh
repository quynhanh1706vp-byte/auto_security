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
cp -f "$F" "${F}.bak_addcontainers_${TS}"
echo "[BACKUP] ${F}.bak_addcontainers_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

need_ids = [
  "vsp-chart-severity",
  "vsp-chart-trend",
  "vsp-chart-bytool",
  "vsp-chart-topcve",
]

# If already present, do nothing
if all(f'id="{i}"' in s for i in need_ids):
    print("[SKIP] containers already exist in source")
    raise SystemExit(0)

block = """
  <!-- VSP_P0_VSP5_REQUIRED_CONTAINERS_V1 -->
  <div id="vsp5_dash_shell" style="padding:12px 14px; display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
    <div id="vsp-chart-severity"></div>
    <div id="vsp-chart-trend"></div>
    <div id="vsp-chart-bytool"></div>
    <div id="vsp-chart-topcve"></div>
  </div>
  <!-- /VSP_P0_VSP5_REQUIRED_CONTAINERS_V1 -->
"""

# Insert right after vsp5_root container in the HTML string
s2, n = re.subn(r'(<div\s+id="vsp5_root"\s*>\s*</div>)', r'\1\n' + block, s, count=1)
if n == 0:
    raise SystemExit("[ERR] cannot find <div id=\"vsp5_root\"></div> to inject containers")

p.write_text(s2, encoding="utf-8")
print("[OK] injected required containers after #vsp5_root")
PY

python3 -m py_compile "$F"
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: html must contain container ids =="
curl -fsS "$BASE/vsp5" | grep -n 'vsp-chart-severity' | head -n 2
echo "[DONE] Ctrl+Shift+R /vsp5"
