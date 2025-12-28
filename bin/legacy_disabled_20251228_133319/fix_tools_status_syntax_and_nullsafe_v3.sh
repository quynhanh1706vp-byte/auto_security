#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tools_status_from_gate_p0_v1.js"
B="$(ls -1t ${F}.bak_blankfix_* 2>/dev/null | head -n1 || true)"
[ -n "$B" ] || { echo "[ERR] cannot find backup ${F}.bak_blankfix_*"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_before_restore_${TS}" && echo "[BACKUP] ${F}.bak_before_restore_${TS}"
cp -f "$B" "$F" && echo "[RESTORE] $F <= $B"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "__VSP_DUMMY_EL__" not in s:
    helper = r"""
  // __VSP_DUMMY_EL__: prevents null crashes when mount points are hidden/missing
  const __VSP_DUMMY_EL__ = {
    textContent: "", innerHTML: "", style: {},
    classList: { add(){}, remove(){}, toggle(){} },
    setAttribute(){}, removeAttribute(){},
    appendChild(){}, prepend(){}, remove(){},
    querySelector(){ return null; }, querySelectorAll(){ return []; }
  };
  function __vsp_q(sel){
    try { return document.querySelector(sel) || __VSP_DUMMY_EL__; }
    catch(_) { return __VSP_DUMMY_EL__; }
  }
  function __vsp_id(id){
    try { return document.getElementById(id) || __VSP_DUMMY_EL__; }
    catch(_) { return __VSP_DUMMY_EL__; }
  }
"""
    m=re.search(r"(['\"]use strict['\"];)", s)
    if m:
        s = s[:m.end()] + helper + s[m.end():]
    else:
        s = helper + "\n" + s

# Replace selectors safely (do NOT touch .textContent assignments, avoid template literal issues)
s = s.replace("document.querySelector(", "__vsp_q(")
s = s.replace("document.getElementById(", "__vsp_id(")

p.write_text(s, encoding="utf-8")
print("[OK] injected dummy selector helpers + rewired querySelector/getElementById")
PY

node --check "$F" && echo "[OK] node --check tools_status" || { echo "[ERR] tools_status still syntax-broken"; exit 3; }

echo "[DONE] tools_status fixed (syntax + null-safe). Now hard refresh (Ctrl+Shift+R) + Ctrl+0."
