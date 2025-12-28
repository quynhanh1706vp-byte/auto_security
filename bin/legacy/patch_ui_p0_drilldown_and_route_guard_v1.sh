#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_p0_route_drill_${TS}"
echo "[BACKUP] $F.bak_p0_route_drill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_enhance_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")
changed = 0

# Inject helpers before final "})();"
if "function VSP_DASH_IS_ACTIVE_P0()" not in s:
    m = re.search(r"\n\}\)\(\);\s*$", s)
    if m:
        inject = r'''
  // =============================
  // P0 ROUTE GUARD (Dashboard-only)
  function VSP_DASH_IS_ACTIVE_P0(){
    try{
      const h = (location.hash || "").toLowerCase();
      // dashboard when empty/#/#dashboard
      if (!h || h === "#" || h === "#dashboard") return true;
      return false;
    }catch(_){ return false; }
  }
  function VSP_DASH_P0_GUARD(reason){
    if (!VSP_DASH_IS_ACTIVE_P0()){
      try{ console.info("[VSP_DASH][P0] skip:", reason, "hash=", location.hash); }catch(_){}
      return false;
    }
    return true;
  }
  // =============================
'''
        s = s[:m.start()] + inject + s[m.start():]
        changed += 1

# After log "[VSP_DASH] Hydrating dashboard (auto fetch)" add guard-return
pat_hyd = r'(\[VSP_DASH\]\s*Hydrating dashboard\s*\(auto fetch\)[^\n]*\n)'
if re.search(pat_hyd, s) and "VSP_DASH_P0_GUARD(\"hydrate\")" not in s:
    s = re.sub(pat_hyd, r'\1  if (!VSP_DASH_P0_GUARD("hydrate")) { return; }\n', s, count=1)
    changed += 1

# Fix drilldown stub: guarantee function to avoid "is not a function"
pat_stub = r'(console\.warn\(\s*"\[VSP_DASH\]\s*drilldown forced stub \(window\)"\s*\);\s*)'
if re.search(pat_stub, s) and "P0_DRILLDOWN_STUB" not in s:
    stub = r'''
\1  // P0_DRILLDOWN_STUB: guarantee callable function
  if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
    window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
      try{ console.warn("[VSP_DASH][P0] drilldown stub used (no-op)"); }catch(_){}
      return { open:function(){}, show:function(){}, destroy:function(){} };
    };
  }
'''
    s = re.sub(pat_stub, stub, s, count=1)
    changed += 1

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p, "changed_blocks=", changed)
PY

node --check "$F" >/dev/null
echo "[OK] node --check $F"
