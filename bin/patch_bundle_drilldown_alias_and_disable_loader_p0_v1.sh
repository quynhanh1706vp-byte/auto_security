#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH COMMERCIAL STABILITY (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

B="static/js/vsp_bundle_commercial_v1.js"
L="static/js/vsp_ui_loader_route_v1.js"
R="static/js/vsp_tabs_hash_router_v1.js"

[ -f "$B" ] || { echo "[ERR] missing bundle: $B"; exit 2; }

# (1) Prepend bundle prologue: flag + drilldown aliases
python3 - <<'PY'
from pathlib import Path
import datetime

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "/* VSP_BUNDLE_COMMERCIAL_V1_PROLOGUE */"
if marker in s:
  print("[OK] bundle already has prologue (skip)")
  raise SystemExit(0)

pro = []
pro.append("/* VSP_BUNDLE_COMMERCIAL_V1_PROLOGUE */")
pro.append(f"/* injected_at: {datetime.datetime.now().isoformat()} */")
pro.append("(function(){")
pro.append("  'use strict';")
pro.append("  try{ window.__VSP_BUNDLE_COMMERCIAL_V1 = true; }catch(_){ }")
pro.append("  // single entrypoint contract")
pro.append("  if (!window.VSP_DRILLDOWN) {")
pro.append("    window.VSP_DRILLDOWN = function(intent){")
pro.append("      try{")
pro.append("        if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);")
pro.append("        if (typeof window.__VSP_DD_ART_CALL__ === 'function') return window.__VSP_DD_ART_CALL__(intent);")
pro.append("        if (typeof window.__VSP_DRILLDOWN__ === 'function') return window.__VSP_DRILLDOWN__(intent);")
pro.append("        console.warn('[VSP][DRILLDOWN] no impl', intent);")
pro.append("        return null;")
pro.append("      }catch(e){ try{console.warn('[VSP][DRILLDOWN] err', e);}catch(_e){} return null; }")
pro.append("    };")
pro.append("  }")
pro.append("  // HARD ALIASES for legacy callers (stop TypeError)")
pro.append("  var alias = function(){ return window.VSP_DRILLDOWN.apply(window, arguments); };")
pro.append("  try{")
pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = alias;")
pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1 = alias;")
pro.append("    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS !== 'function') window.VSP_DASH_DRILLDOWN_ARTIFACTS = alias;")
pro.append("  }catch(_){ }")
pro.append("})();")
pro.append("")

p.write_text("\n".join(pro) + "\n" + s, encoding="utf-8")
print("[OK] injected bundle prologue + drilldown aliases")
PY

# (2) Disable dynamic loader if bundle flag present
if [ -f "$L" ]; then
  python3 - <<'PY'
from pathlib import Path
import datetime, re

p = Path("static/js/vsp_ui_loader_route_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "/* VSP_LOADER_BUNDLE_GUARD_P0_V1 */"
if marker in s:
  print("[OK] loader already guarded (skip)")
  raise SystemExit(0)

guard = []
guard.append("/* VSP_LOADER_BUNDLE_GUARD_P0_V1 */")
guard.append(f"/* injected_at: {datetime.datetime.now().isoformat()} */")
guard.append("(function(){")
guard.append("  try{ if (window && window.__VSP_BUNDLE_COMMERCIAL_V1) {")
guard.append("    console.log('[VSP_LOADER] commercial bundle present -> skip route loader');")
guard.append("    return;")
guard.append("  }}catch(_){ }")
guard.append("})();")
guard.append("")

# put guard at top
p.write_text("\n".join(guard) + "\n" + s, encoding="utf-8")
print("[OK] guarded vsp_ui_loader_route_v1.js")
PY
else
  echo "[WARN] missing $L (skip loader guard)"
fi

# (3) Optional: guard router too (avoid double-init spam)
if [ -f "$R" ]; then
  python3 - <<'PY'
from pathlib import Path
import datetime

p = Path("static/js/vsp_tabs_hash_router_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "/* VSP_ROUTER_BUNDLE_GUARD_P0_V1 */"
if marker in s:
  print("[OK] router already guarded (skip)")
  raise SystemExit(0)

guard = []
guard.append("/* VSP_ROUTER_BUNDLE_GUARD_P0_V1 */")
guard.append(f"/* injected_at: {datetime.datetime.now().isoformat()} */")
guard.append("(function(){")
guard.append("  try{ if (window && window.__VSP_BUNDLE_COMMERCIAL_V1) {")
guard.append("    console.log('[VSP_TABS_ROUTER] commercial bundle present -> skip standalone router');")
guard.append("    return;")
guard.append("  }}catch(_){ }")
guard.append("})();")
guard.append("")

p.write_text("\n".join(guard) + "\n" + s, encoding="utf-8")
print("[OK] guarded vsp_tabs_hash_router_v1.js")
PY
fi

echo "== node --check bundle =="
node --check static/js/vsp_bundle_commercial_v1.js && echo "[OK] bundle OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + hard refresh Ctrl+Shift+R, then open /vsp4#dashboard and confirm console clean."
