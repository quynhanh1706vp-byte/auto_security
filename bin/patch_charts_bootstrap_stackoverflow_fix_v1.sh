#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_dashboard_charts_bootstrap_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "$JS.bak_stackfix_${TS}"
echo "[BACKUP] $JS.bak_stackfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_charts_bootstrap_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_BOOTSTRAP_STACKFIX_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# 1) remove any dispatch we injected earlier (to stop event storms)
t = re.sub(r"\n\s*try\{\s*window\.dispatchEvent\(new CustomEvent\(\s*['\"]vsp:charts-ready['\"][\s\S]*?\)\);\s*\}\s*catch\(e\)\{\}\s*\n", "\n", t, flags=re.M)

# 2) add global guard + scheduleTick helper near top (after first IIFE/opening)
ins = TAG + r"""
(function(){
  try{
    if (window.__VSP_BOOTSTRAP_STACKFIX_V1) return;
    window.__VSP_BOOTSTRAP_STACKFIX_V1 = true;
  }catch(e){}
})();
var __vsp_boot_tick_running = false;
var __vsp_boot_tick_scheduled = false;
function __vsp_boot_scheduleTick(fn){
  try{
    if (__vsp_boot_tick_scheduled) return;
    __vsp_boot_tick_scheduled = true;
    setTimeout(function(){
      __vsp_boot_tick_scheduled = false;
      fn();
    }, 0);
  }catch(e){
    try{ fn(); }catch(_){}
  }
}
"""
if TAG not in t:
    t = ins + "\n" + t

# 3) wrap calls to tick() to scheduleTick() (avoid deep recursion)
# replace standalone "tick();" but NOT the function definition line.
t = re.sub(r"(?m)^(?!\s*function\s+tick\s*\()\s*(tick\(\)\s*;)\s*$",
           lambda m: m.group(0).replace("tick();", "__vsp_boot_scheduleTick(tick);"),
           t)

# 4) add reentry guard at start of tick()
# find "function tick(" then insert guard lines right after opening brace
t = re.sub(r"(function\s+tick\s*\(\s*\)\s*\{\s*)",
           r"\1\n  if (__vsp_boot_tick_running) return;\n  __vsp_boot_tick_running = true;\n  try{\n",
           t, count=1)

# ensure we close the try/finally before tick() ends (best effort: inject before first line that closes tick with "}")
# add finally just before the first "}\n" that likely ends tick (but avoid breaking other blocks by requiring indentation 0-2)
t = re.sub(r"(?m)^\}\s*$",
           "  } finally {\n    __vsp_boot_tick_running = false;\n  }\n}\n",
           t, count=1)

p.write_text(t, encoding="utf-8")
print("[OK] patched bootstrap to avoid recursion + stop charts-ready storm")
PY

echo "[OK] patch applied"
systemctl --user restart vsp-ui-8910.service
sleep 1
echo "[OK] restart done"
