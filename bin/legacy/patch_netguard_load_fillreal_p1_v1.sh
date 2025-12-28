#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_P1_LOAD_FILLREAL_FROM_NETGUARD_P1_V1"
tpl=Path("templates")
if not tpl.is_dir():
    raise SystemExit("[ERR] templates/ not found")

files=[]
for p in tpl.rglob("*.html"):
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P1_NETGUARD_GLOBAL_V7C" in s:
        files.append(p)

if not files:
    raise SystemExit("[ERR] cannot find templates containing VSP_P1_NETGUARD_GLOBAL_V7C")

snippet = r'''
  // VSP_P1_LOAD_FILLREAL_FROM_NETGUARD_P1_V1
  try{
    if (!window.__vsp_fillreal_loader_from_netguard_p1_v1){
      window.__vsp_fillreal_loader_from_netguard_p1_v1 = true;
      var s=document.createElement('script');
      s.src='/static/js/vsp_fill_real_data_5tabs_p1_v1.js';
      s.defer=true;
      (document.head||document.documentElement).appendChild(s);
    }
  }catch(_){}
'''

patched=[]
for p in files:
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue

    # Insert right after the guard sets window.__vsp_p1_netguard_global_v7c = true;
    pat = r"(window\.__vsp_p1_netguard_global_v7c\s*=\s*true\s*;\s*)"
    if re.search(pat, s):
        s2 = re.sub(pat, r"\1\n" + snippet, s, count=1)
    else:
        # fallback: insert near start of that script block
        s2 = s.replace("window.__vsp_p1_netguard_global_v7c = true;",
                       "window.__vsp_p1_netguard_global_v7c = true;\n"+snippet)

    bak = Path(str(p) + f".bak_fillreal_netguard_{int(time.time())}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    patched.append(str(p))

print("[OK] patched:", len(patched))
for x in patched[:30]:
    print(" -", x)
PY
