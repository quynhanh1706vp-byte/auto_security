#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_drillguard_${TS}" && echo "[BACKUP] $F.bak_drillguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_DRILLDOWN_GUARD_V1" in s:
    print("[OK] guard already present")
    raise SystemExit(0)

guard = r"""
  // VSP_DRILLDOWN_GUARD_V1: prevent patch-chồng overwrite from breaking dashboard
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function'){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){ return false; };
    }
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P0_V1 !== 'function'){
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P0_V1 = function(){ return false; };
    }
  }catch(_){}
"""

# inject right after first 'use strict';
m = re.search(r"(['\"]use strict['\"]\s*;)", s)
if not m:
    # fallback: inject after first IIFE open
    m = re.search(r"\(function\(\)\s*\{\s*", s)
    if not m:
        raise SystemExit("[ERR] cannot find inject point")
    idx = m.end()
    s2 = s[:idx] + "\n" + guard + "\n" + s[idx:]
else:
    idx = m.end()
    s2 = s[:idx] + "\n" + guard + "\n" + s[idx:]

p.write_text(s2, encoding="utf-8")
print("[OK] injected drilldown guard into vsp_dashboard_enhance_v1.js")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK"

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "[NEXT] Ctrl+Shift+R, and (optional) uncheck Preserve log to confirm red error gone."
