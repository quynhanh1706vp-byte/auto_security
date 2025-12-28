#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_gate_${TS}"
echo "[BACKUP] $F.bak_kpi_gate_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_KPI_FROM_GATE_COUNTS_P0_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_KPI_FROM_GATE_COUNTS_P0_V2: normalize dashboard payload */
(function(){
  try{
    if (window.__vspNormalizeDash) return;
    window.__vspNormalizeDash = function(d){
      try{
        if(!d || typeof d!=="object") return d;
        const c = d?.gate?.counts_total || d?.gate?.counts || null;
        if(!c || typeof c!=="object") return d;

        const CR = +c.CRITICAL||0, HI=+c.HIGH||0, ME=+c.MEDIUM||0, LO=+c.LOW||0, IN=+c.INFO||0, TR=+c.TRACE||0;
        const total = CR+HI+ME+LO+IN+TR;

        d.by_severity = d.by_severity || {CRITICAL:CR,HIGH:HI,MEDIUM:ME,LOW:LO,INFO:IN,TRACE:TR};
        d.kpi = d.kpi || {};
        d.kpi.total = (d.kpi.total ?? total);
        d.kpi.critical = (d.kpi.critical ?? CR);
        d.kpi.high = (d.kpi.high ?? HI);
        d.kpi.medium = (d.kpi.medium ?? ME);
        d.kpi.low = (d.kpi.low ?? LO);
        d.kpi.info = (d.kpi.info ?? IN);
        d.kpi.trace = (d.kpi.trace ?? TR);

        const degr = d?.degraded?.any ?? d?.kpi?.degraded ?? d?.degraded ?? null;
        if (degr !== null && d.kpi.degraded === undefined) d.kpi.degraded = degr;

        return d;
      }catch(_){ return d; }
    };
  }catch(_){}
})();
'''

# put after first 'use strict'; else prepend
m = re.search(r"(['\"])use strict\1\s*;\s*", s)
if m:
    i = m.end()
    s = s[:i] + inject + s[i:]
else:
    s = inject + "\n" + s

# Try to wrap render/update calls first
patched = {"done": False}
patterns = [
    r"(renderDashboard\s*\(\s*)([a-zA-Z_]\w*)(\s*\))",
    r"(updateDashboard\s*\(\s*)([a-zA-Z_]\w*)(\s*\))",
    r"(renderCommercialDashboard\s*\(\s*)([a-zA-Z_]\w*)(\s*\))",
]
for pat in patterns:
    def repl(m):
        patched["done"] = True
        arg = m.group(2)
        return f"{m.group(1)}window.__vspNormalizeDash({arg}){m.group(3)}"
    s2 = re.sub(pat, repl, s, count=1)
    if s2 != s:
        s = s2
        break

# If none matched, normalize at first .then(function(data){ ... })
if not patched["done"]:
    def then_repl(m):
        var = m.group(2)
        return m.group(1) + f"{var} = window.__vspNormalizeDash({var});\n"
    s2 = re.sub(r"(\.then\(\s*function\s*\(\s*([a-zA-Z_]\w*)\s*\)\s*\{\s*)",
                then_repl, s, count=1)
    if s2 != s:
        s = s2
        patched["done"] = True

s += f"\n/* {MARK} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK, "hook=", patched["done"])
PY

node --check "$F"
echo "[OK] node --check OK"

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4  (KPI should show HIGH=43, TOTAL=43)"
