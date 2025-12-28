#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ridguard_v2_${TS}"
echo "[BACKUP] ${JS}.bak_ridguard_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_DEGRADED_RID_GUARD_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Helper getter (safe)
getter = r"""
/* VSP_P0_DEGRADED_RID_GUARD_V2 */
window.__vspGetRidSafe = window.__vspGetRidSafe || function(){
  try{
    const u = new URL(window.location.href);
    return (u.searchParams.get("rid") || "").trim();
  }catch(e){ return ""; }
};
""".strip() + "\n"

# Insert getter near top
if "use strict" in s:
    s = re.sub(r'(["\']use strict["\'];\s*)', r'\1\n' + getter + "\n", s, count=1)
else:
    s = getter + "\n" + s

def inject_at_fn_start(text: str, pat: re.Pattern) -> str:
    m = pat.search(text)
    if not m: return text
    start = m.end()
    head = text[start:start+400]
    # if already has rid declared near start, skip
    if re.search(r'\b(var|let|const)\s+rid\b', head):
        return text
    inj = """
  var rid = (window.__VSP_RID || (window.__vspGetRidSafe && window.__vspGetRidSafe()) || "");
  if(!rid){ return; }
""".rstrip() + "\n"
    return text[:start] + "\n" + inj + text[start:]

# Patterns: normal function assignment + arrow/async arrow assignment
patterns = [
    re.compile(r'(window\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*\{)'),
    re.compile(r'(window\.__vspCheckDegraded\s*=\s*async\s*function\s*\([^)]*\)\s*\{)'),
    re.compile(r'(window\.__vspCheckDegraded\s*=\s*\([^)]*\)\s*=>\s*\{)'),
    re.compile(r'(window\.__vspCheckDegraded\s*=\s*async\s*\([^)]*\)\s*=>\s*\{)'),
    # some builds attach to document
    re.compile(r'(document\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*\{)'),
    re.compile(r'(document\.__vspCheckDegraded\s*=\s*async\s*function\s*\([^)]*\)\s*\{)'),
    re.compile(r'(document\.__vspCheckDegraded\s*=\s*\([^)]*\)\s*=>\s*\{)'),
    re.compile(r'(document\.__vspCheckDegraded\s*=\s*async\s*\([^)]*\)\s*=>\s*\{)'),
]
before = s
for pat in patterns:
    s = inject_at_fn_start(s, pat)

# If nothing changed (still not matched), add ultra-safe top-scope rid for this script (low risk)
if s == before:
    # add just after getter block (first occurrence)
    add = r"""
/* VSP_P0_DEGRADED_RID_FALLBACK_TOP_V2 */
var rid = (function(){
  try{
    var u = new URL(window.location.href);
    return (window.__VSP_RID || u.searchParams.get("rid") || "").toString().trim();
  }catch(e){
    return (window.__VSP_RID || "").toString();
  }
})();
""".strip() + "\n"
    s = s.replace(getter, getter + "\n" + add, 1)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P0_DEGRADED_RID_GUARD_V2" "$JS" | head -n 2 && echo "[OK] marker present"
