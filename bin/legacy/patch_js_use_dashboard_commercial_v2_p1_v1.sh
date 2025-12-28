#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_dashv2_${TS}"
echo "[BACKUP] $F.bak_dashv2_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_DASH_USE_COMMERCIAL_V2_P1_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

s=s.replace("/api/vsp/dashboard_commercial_v1", "/api/vsp/dashboard_commercial_v2", 1)
if "/api/vsp/dashboard_commercial_v2" not in s:
    print("[ERR] cannot patch (no v1 found)"); raise SystemExit(2)

# drop a marker comment near the first occurrence
s=s.replace("/api/vsp/dashboard_commercial_v2", "/api/vsp/dashboard_commercial_v2/*"+MARK+"*/", 1)
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$F"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R /vsp4#dashboard → DEGRADED nên về NO (trừ khi findings hỏng)."
