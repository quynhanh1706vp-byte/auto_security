#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_netguard_loader_${TS}"
echo "[BACKUP] ${F}.bak_netguard_loader_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_LOAD_FILLREAL_FROM_NETGUARD_P1_V2"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# loader snippet: safe inside JS; no triple quotes
snippet = r'''
  // VSP_P1_LOAD_FILLREAL_FROM_NETGUARD_P1_V2
  try{
    if (!window.__vsp_fillreal_loader_from_netguard_p1_v2){
      window.__vsp_fillreal_loader_from_netguard_p1_v2 = true;
      var _s=document.createElement("script");
      _s.src="/static/js/vsp_fill_real_data_5tabs_p1_v1.js";
      _s.defer=true;
      (document.head||document.documentElement).appendChild(_s);
    }
  }catch(_){}
'''

# Insert right after the "set guard true" line wherever it exists in the file
pat = r'(window\.__vsp_p1_netguard_global_v7c\s*=\s*true\s*;\s*)'
m = re.search(pat, s)
if not m:
    # fallback: any assignment to __vsp_p1_netguard_global_v7c
    pat2 = r'(__vsp_p1_netguard_global_v7c\s*=\s*true\s*;\s*)'
    m2 = re.search(pat2, s)
    if not m2:
        raise SystemExit("[ERR] cannot find assignment line for __vsp_p1_netguard_global_v7c in wsgi_vsp_ui_gateway.py")
    s2 = re.sub(pat2, r"\1\n"+snippet, s, count=1)
else:
    s2 = re.sub(pat, r"\1\n"+snippet, s, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] injected loader into NETGUARD in wsgi:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
