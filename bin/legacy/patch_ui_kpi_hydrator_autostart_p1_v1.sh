#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_autostart_${TS}" && echo "[BACKUP] $F.bak_kpi_autostart_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_KPI_HYDRATOR_AUTOSTART_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# Limit patch scope to the first hydrator block (near top)
head = s[:8000]
tail = s[8000:]

# Find a DOMContentLoaded listener in the head (hydrator init)
pat1 = re.compile(r'document\.addEventListener\(\s*["\']DOMContentLoaded["\']\s*,\s*function\s*\(\)\s*\{[\s\S]*?\}\s*\)\s*;', re.M)
pat2 = re.compile(r'document\.addEventListener\(\s*["\']DOMContentLoaded["\']\s*,\s*\(\s*\)\s*=>\s*\{[\s\S]*?\}\s*\)\s*;', re.M)

m = pat1.search(head) or pat2.search(head)
if not m:
    raise SystemExit("[ERR] cannot find DOMContentLoaded listener in first 8000 chars (hydrator init not found)")

orig = head[m.start():m.end()]

# We assume the listener body calls hydrate/_run with timers. Replace with readyState auto-start.
replacement = r'''
// === VSP_KPI_HYDRATOR_AUTOSTART_P1_V1 ===
function _vspStartKpiHydrator(){
  try{
    // run immediately + retry; keep interval for SPA pane mount
    if (typeof _run === "function") _run();
    else if (typeof hydrate === "function") hydrate();
  }catch(_){}
  try{
    setTimeout(function(){ try{ (typeof _run==="function")?_run(): (typeof hydrate==="function")?hydrate():0; }catch(_){} }, 250);
    setTimeout(function(){ try{ (typeof _run==="function")?_run(): (typeof hydrate==="function")?hydrate():0; }catch(_){} }, 800);
    setTimeout(function(){ try{ (typeof _run==="function")?_run(): (typeof hydrate==="function")?hydrate():0; }catch(_){} }, 1600);
    setInterval(function(){ try{ (typeof _run==="function")?_run(): (typeof hydrate==="function")?hydrate():0; }catch(_){} }, 2000);
  }catch(_){}
}

try{
  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", _vspStartKpiHydrator);
  }else{
    setTimeout(_vspStartKpiHydrator, 0);
  }
}catch(_){}
'''

head2 = head[:m.start()] + replacement + "\n" + orig + "\n// " + marker + "\n" + head[m.end():]
s2 = head2 + tail

p.write_text(s2, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
