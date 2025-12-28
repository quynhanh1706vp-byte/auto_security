#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ridguard_${TS}"
echo "[BACKUP] ${JS}.bak_ridguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DEGRADED_RID_GUARD_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Add rid getter (once)
getter = r"""
/* VSP_P0_DEGRADED_RID_GUARD_V1 */
window.__vspGetRidSafe = window.__vspGetRidSafe || function(){
  try{
    const u = new URL(window.location.href);
    return (u.searchParams.get("rid") || "").trim();
  }catch(e){ return ""; }
};
""".strip()+"\n"

# Insert near top (after "use strict" if present)
if "use strict" in s:
    s = re.sub(r'(["\']use strict["\'];\s*)', r'\1\n' + getter + "\n", s, count=1)
else:
    s = getter + "\n" + s

def inject_into_fn(def_pat: re.Pattern, text: str) -> str:
    m = def_pat.search(text)
    if not m:
        return text
    start = m.end()
    head = text[start:start+300]
    # If rid already declared in first part of function, skip
    if re.search(r'\b(var|let|const)\s+rid\b', head):
        return text
    inj = """
  var rid = (window.__VSP_RID || (window.__vspGetRidSafe && window.__vspGetRidSafe()) || "");
  if(!rid){ return; }
""".rstrip()+"\n"
    return text[:start] + "\n" + inj + text[start:]

# 2) Inject rid declare inside __vspCheckDegraded (several possible styles)
patterns = [
    re.compile(r'(window\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*\{)'),
    re.compile(r'(\bfunction\s+__vspCheckDegraded\s*\([^)]*\)\s*\{)'),
    re.compile(r'(document\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*\{)'),
]
for pat in patterns:
    s2 = inject_into_fn(pat, s)
    s = s2

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P0_DEGRADED_RID_GUARD_V1" "$JS" | head -n 2 && echo "[OK] marker present"
