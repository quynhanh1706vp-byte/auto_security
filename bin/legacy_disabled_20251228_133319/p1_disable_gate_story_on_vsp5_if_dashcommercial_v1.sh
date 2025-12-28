#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_disable_${TS}"
echo "[BACKUP] ${F}.bak_disable_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DISABLE_GATE_STORY_IF_DASHCOMM_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

# Patch the first IIFE opener: (()=> {  OR (() => {  OR (function(){ ...
# We inject a guard INSIDE the function so 'return' is valid.
guard = r'''
/* %s */
try{
  const path = (location && location.pathname) ? location.pathname : "";
  const hasDash = !!document.querySelector('script[src*="vsp_dashboard_commercial_v1.js"]') || !!window.__vsp_dash_commercial_v1_loaded;
  if (path === "/vsp5" || hasDash){
    console.log("[GateStoryV1] disabled (DashCommercialV1 present or /vsp5).");
    return;
  }
}catch(e){}
''' % marker

# Replace first occurrence of an arrow-IIFE start: (()=>{ or (() => {
m = re.search(r'\(\s*\(\s*\)\s*=>\s*\{', s)
if m:
    idx = m.end()
    s2 = s[:idx] + "\n" + guard + "\n" + s[idx:]
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected guard into arrow IIFE")
    raise SystemExit(0)

# Fallback: function IIFE (function(){ ... })();
m = re.search(r'\(\s*function\s*\(\s*\)\s*\{', s, flags=re.I)
if m:
    idx = m.end()
    s2 = s[:idx] + "\n" + guard + "\n" + s[idx:]
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected guard into function IIFE")
    raise SystemExit(0)

raise SystemExit("[ERR] cannot find IIFE opener to patch (unexpected file shape)")
PY

echo "[DONE] GateStory kill-switch applied."
echo "Next: restart UI then hard refresh /vsp5."
