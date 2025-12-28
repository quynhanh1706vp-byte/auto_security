#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_keepalive_${TS}"
echo "[BACKUP] ${JS}.bak_keepalive_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP5_RUNS_REPORTS_KEEPALIVE_P0_V3"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Inject keepalive scheduling inside the VSP5 enhancer boot() just before end.
# We search for "async function boot()" block and add timers.
m=re.search(r"async function boot\(\)\{\n([\s\S]*?)\n\s*\}\n\n\s*if \(document\.readyState", s)
if not m:
    raise SystemExit("[ERR] cannot locate boot() in VSP5 enhancer")

boot_body=m.group(1)
ins = r"""
    // VSP5_RUNS_REPORTS_KEEPALIVE_P0_V3
    // Keep re-applying because vsp_bundle_commercial_v2.js may rerender rows after we patch.
    try{
      let n=0;
      const fast = setInterval(()=>{ enhanceOnce(); n++; if(n>=15) clearInterval(fast); }, 800);
      setInterval(()=>{ enhanceOnce(); }, 3000);
    }catch(e){}
"""
# Add right after installObserver(); line if present else at start.
if "installObserver();" in boot_body:
    boot_body2 = boot_body.replace("installObserver();", "installObserver();\n"+ins)
else:
    boot_body2 = ins + "\n" + boot_body

s2 = s[:m.start(1)] + boot_body2 + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
print("[OK] keepalive injected:", MARK)
PY

node --check "$JS"
echo "[OK] node --check OK"
sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restart done; now Ctrl+F5 /vsp5"
