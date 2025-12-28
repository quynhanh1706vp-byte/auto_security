#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
TPL="templates/vsp_dashboard_2025.html"
MARK="VSP_TOPNAV_DATASOURCE_TO_DATA_P0_V1"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_${MARK}_${TS}"
echo "[BACKUP] $TPL.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="replace")
# replace only inside the injected topnav block
i=s.find("VSP_TOPNAV_5TABS_P0_V1")
if i<0: raise SystemExit("[ERR] cannot find topnav marker")
j=s.find("<!-- /VSP_TOPNAV_5TABS_P0_V1 -->", i)
if j<0: j=i+2000
block=s[i:j]
block2=re.sub(r'href="/vsp5"([^>]*>)\s*Data Source', r'href="/data"\1 Data Source', block, count=1)
if block2==block:
    print("[WARN] no Data Source link replaced (maybe already /data)")
else:
    s=s[:i]+block2+s[j:]
    p.write_text(s, encoding="utf-8")
    print("[OK] Data Source link -> /data")
PY
echo "[OK] done"
