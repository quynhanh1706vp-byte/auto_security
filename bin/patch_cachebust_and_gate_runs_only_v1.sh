#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_cachebust_gate_${TS}"
echo "[BACKUP] $TPL.bak_cachebust_gate_${TS}"

echo "== [1/3] cachebust template for critical JS =="
python3 - <<PY
from pathlib import Path
import re
p=Path("$TPL")
s=p.read_text(encoding="utf-8", errors="ignore")

def bump(name):
    global s
    # replace any existing querystring with new v=TS, or add if none
    s = re.sub(rf'({re.escape(name)})(\?[^"\']*)?', rf'\1?v=$TS', s)

for js in [
  "vsp_tools_status_from_gate_p0_v1.js",
  "vsp_tool_pills_verdict_from_gate_p0_v1.js",
  "vsp_tool_pills_verdict_from_gate_p0_v2.js",
  "vsp_degraded_panel_hook_v3.js",
  "vsp_commercial_layout_controller_v1.js",
]:
    bump(js)

# also bump any vsp_runs_*.js occurrences (best effort)
s = re.sub(r'(vsp_runs_[^"\']+?\.js)(\?[^"\']*)?', rf'\1?v=$TS', s)

p.write_text(s, encoding="utf-8")
print("[OK] cachebusted in template:", p)
PY

echo "== [2/3] gate vsp_runs_* scripts to #runs only (IIFE-safe) =="
python3 - <<'PY'
from pathlib import Path
import time

root = Path("static/js")
targets = sorted([p for p in root.glob("vsp_runs_*.js") if p.is_file()])

def is_iife(code:str)->bool:
    head = code[:1200]
    return "(function" in head or "(()=>{" in head or "(async function" in head

def inject_guard(code:str, fname:str)->str:
    if "VSP_ROUTE_GUARD_RUNS_ONLY_V1" in code:
        return code
    guard = f"""
  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){{
    try {{
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    }} catch(_) {{ return false; }}
  }}
  if(!__vsp_is_runs_only_v1()){{
    try{{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "{fname}", "hash=", location.hash); }}catch(_){{}}
    return;
  }}
"""
    if "'use strict';" in code:
        return code.replace("'use strict';", "'use strict';\n"+guard, 1)
    if '"use strict";' in code:
        return code.replace('"use strict";', '"use strict";\n'+guard, 1)
    # fallback: insert after first line of IIFE body
    return code.replace("{", "{\n"+guard, 1)

patched = 0
ts=time.strftime("%Y%m%d_%H%M%S")
for p in targets:
    code = p.read_text(encoding="utf-8", errors="ignore")
    if not is_iife(code):
        # don't risk top-level return
        continue
    new = inject_guard(code, p.name)
    if new != code:
        bak = p.with_suffix(p.suffix + f".bak_gate_{ts}")
        bak.write_text(code, encoding="utf-8")
        p.write_text(new, encoding="utf-8")
        print("[OK] gated", p.name, "backup=>", bak.name)
        patched += 1

print("[DONE] gated runs files =", patched, " (only IIFE files patched)")
PY

echo "== [3/3] quick syntax check on patched files (best-effort) =="
node --check static/js/vsp_tools_status_from_gate_p0_v1.js >/dev/null 2>&1 && echo "[OK] node --check tools_status" || echo "[WARN] tools_status syntax check failed"
for f in static/js/vsp_runs_*.js; do
  node --check "$f" >/dev/null 2>&1 || echo "[WARN] node --check failed: $f"
done

echo "[DONE] cachebust + gate runs scripts. Restart UI then Ctrl+Shift+R + Ctrl+0."
