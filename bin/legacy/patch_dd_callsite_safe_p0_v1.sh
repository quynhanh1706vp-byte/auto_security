#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_dd_callsite_${TS}"
echo "[BACKUP] $F.bak_dd_callsite_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) ensure safe wrapper exists (only if missing)
helper = r"""
/* __VSP_DD_ART_CALL__ (P0): safe-call drilldown artifacts handler (function OR object.open) */
function __VSP_DD_ART_CALL__(h, ...args) {
  try {
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
  } catch(e) { try{ console.warn('[VSP][DD_SAFE_CALL]', e); }catch(_e){} }
  return null;
}
"""
if "__VSP_DD_ART_CALL__(" not in s:
    m=re.search(r"'use strict'\s*;", s)
    if m:
        s = s[:m.end()] + "\n" + helper + "\n" + s[m.end():]
    else:
        s = helper + "\n" + s

# 2) wrap bare callsites: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...)
# avoid touching function declarations or obj.property uses
pat = re.compile(r"(?<!function\s)(?<![\w\.\$])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", re.M)
s, n1 = pat.subn("__VSP_DD_ART_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2,", s)

# also wrap accidental window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...)
pat2 = re.compile(r"(?<!function\s)(?<![\w\.\$])window\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", re.M)
s, n2 = pat2.subn("__VSP_DD_ART_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2,", s)

p.write_text(s, encoding="utf-8")
print("[PATCH] wrapped_local_calls =", n1)
print("[PATCH] wrapped_window_calls=", n2)
PY

node --check "$F" && echo "[OK] node --check"

# restart (prefer hard reset if you have it)
if [ -x bin/restart_ui_8910_hard_reset_v1.sh ]; then
  bash bin/restart_ui_8910_hard_reset_v1.sh
elif [ -x bin/restart_ui_8910_lowmem_v2.sh ]; then
  bash bin/restart_ui_8910_lowmem_v2.sh
else
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
fi

echo "[NEXT] Ctrl+Shift+R, kiểm tra Console: không còn 'is not a function' ở :3050"
echo "[CHECK] grep callsites (should be empty):"
echo "  grep -n \"VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(\" -n \"$F\" | head"
