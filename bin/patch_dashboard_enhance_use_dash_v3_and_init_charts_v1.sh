#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_dashv3_init_${TS}"
echo "[BACKUP] $F.bak_dashv3_init_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_dashboard_enhance_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_DASH_USE_DASH_V3_AND_INIT_CHARTS_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# 1) Replace any dashboard_v3_latest usage to dashboard_v3 (safe for UI)
t2 = re.sub(r'(["\'])/api/vsp/dashboard_v3_latest(\1)', r'\1/api/vsp/dashboard_v3\1', t)
t2 = re.sub(r'(["\'])/api/vsp/dashboard_v3_latest\.json(\1)', r'\1/api/vsp/dashboard_v3\1', t2)

# 2) Inject helper to init charts after dashboard data is available.
# Try to insert near the end (before last IIFE close) so we don't break structure.
inject = f"""
{TAG}
(function(){{
  try {{
    if (window.__VSP_DASH_INIT_CHARTS_V1) return;
    window.__VSP_DASH_INIT_CHARTS_V1 = true;

    function _vspGetChartsEngine() {{
      return window.VSP_CHARTS_ENGINE_V3 || window.VSP_CHARTS_ENGINE_V2 || null;
    }}

    window.__VSP_DASH_TRY_INIT_CHARTS_V1 = function(dash, reason) {{
      try {{
        if (dash) window.__VSP_DASH_LAST_DATA_V3 = dash;
        var eng = _vspGetChartsEngine();
        if (!eng || !eng.initAll) return false;
        var d = dash || window.__VSP_DASH_LAST_DATA_V3;
        if (!d) return false;
        var ok = eng.initAll(d);
        console.log("[VSP_DASH] charts initAll via", reason || "unknown", "=>", ok);
        return !!ok;
      }} catch (e) {{
        console.warn("[VSP_DASH] charts init failed", e);
        return false;
      }}
    }};

    // Listen for charts-ready (late engine load)
    window.addEventListener("vsp:charts-ready", function(ev){{
      setTimeout(function(){{
        window.__VSP_DASH_TRY_INIT_CHARTS_V1(null, "charts-ready");
      }}, 0);
    }});
  }} catch(e) {{
    console.warn("[VSP_DASH] init-charts patch failed", e);
  }}
}})();
"""

# Put inject at end of file (safe)
t2 = t2.rstrip() + "\n\n" + inject + "\n"
p.write_text(t2, encoding="utf-8")
print("[OK] patched enhance: use /api/vsp/dashboard_v3 + init charts helper")
PY

node --check "$F"
echo "[OK] node --check passed"
