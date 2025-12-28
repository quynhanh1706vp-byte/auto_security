#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TPL="templates/vsp_dashboard_2025.html"
MARK="VSP_TOPNAV_SELFCHECK_BTN_P0_V1"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}"
echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
MARK="VSP_TOPNAV_SELFCHECK_BTN_P0_V1"
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# Find the injected topnav block and add a Selfcheck link near the right side
# We insert before the last closing </div></div> of the nav block.
nav_start = s.find("VSP_TOPNAV_5TABS_P0_V1")
if nav_start < 0:
    raise SystemExit("[ERR] topnav block not found (VSP_TOPNAV_5TABS_P0_V1)")

# Insert after "VSP 2025" title or before first tab link
ins = s.find('<div style="flex:1"></div>', nav_start)
if ins < 0:
    raise SystemExit("[ERR] cannot find flex spacer in topnav block")

btn = f'''
    <!-- {MARK} -->
    <a href="/api/vsp/selfcheck_p0" target="_blank" rel="noopener"
       style="color:#9fe2ff;text-decoration:none;padding:8px 10px;border-radius:10px;background:rgba(0,255,255,.08);border:1px solid rgba(0,255,255,.15);">
      Selfcheck
    </a>
    <!-- /{MARK} -->
'''
s = s[:ins] + btn + s[ins:]
p.write_text(s, encoding="utf-8")
print("[OK] injected selfcheck button")
PY
echo "[OK] patched $TPL"
