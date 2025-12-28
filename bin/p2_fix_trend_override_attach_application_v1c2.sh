#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need systemctl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_trend_attachapp_${TS}"
echo "[BACKUP] ${W}.bak_trend_attachapp_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TREND_V1_BEFORE_REQUEST_OVERRIDE_V1C"
if MARK not in s:
    print("[ERR] V1C marker not found in file (did you run v1c inject?)")
    raise SystemExit(2)

# Replace the install call to target "application" first.
# Old:
#   _vsp_install_trend_v1_override(globals().get("app"))
# New:
#   _vsp_install_trend_v1_override(globals().get("application") or globals().get("app"))
new = re.sub(
    r'_vsp_install_trend_v1_override\(\s*globals\(\)\.get\("app"\)\s*\)',
    r'_vsp_install_trend_v1_override(globals().get("application") or globals().get("app"))',
    s,
    count=1
)

if new == s:
    # maybe formatting differs; do a broader patch
    new = s.replace(
        '_vsp_install_trend_v1_override(globals().get("app"))',
        '_vsp_install_trend_v1_override(globals().get("application") or globals().get("app"))',
        1
    )

if new == s:
    print("[ERR] could not patch install call inside V1C block")
    raise SystemExit(2)

p.write_text(new, encoding="utf-8")
print("[OK] patched install target to prefer globals().get('application')")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart $SVC =="
sudo systemctl restart "$SVC"

echo "== smoke trend_v1 (must show ok:true + marker) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5" | head -c 260; echo
