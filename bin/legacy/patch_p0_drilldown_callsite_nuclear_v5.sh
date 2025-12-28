#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_p0_drillcall_v5_${TS}"
echo "[BACKUP] $F.bak_p0_drillcall_v5_${TS}"

TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["TARGET_FILE"])
s = p.read_text(encoding="utf-8", errors="ignore")

# Replace ALL call-sites: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...)
# => (typeof X==="function"?X:function(){return {open(){},show(){},close(){},destroy(){}}})(...)
pat = r"\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\("
repl = r'(typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function"?VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2:function(){try{console.info("[VSP_DASH][P0] drilldown missing -> stub");}catch(_){ } return {open(){},show(){},close(){},destroy(){}};})('

s2, n = re.subn(pat, repl, s)
p.write_text(s2, encoding="utf-8")
print("[OK] replaced callsites =", n)
PY

node --check "$F" >/dev/null
echo "[OK] node --check $F"
echo "[DONE] nuclear drilldown v5"
