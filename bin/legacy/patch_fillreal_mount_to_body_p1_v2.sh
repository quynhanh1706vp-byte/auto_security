#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_mountbody_${TS}"
echo "[BACKUP] ${JS}.bak_mountbody_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_FILLREAL_MOUNT_TO_BODY_P1_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# inject a universal mount helper right after style is appended
needle = "document.head.appendChild(st);"
ins = needle + r'''
  // VSP_FILLREAL_MOUNT_TO_BODY_P1_V2
  const __vsp_mount_root = () => {
    try{
      let host = document.getElementById("VSP_FILLREAL_P1_HOST");
      if (host) return host;
      host = document.createElement("div");
      host.id = "VSP_FILLREAL_P1_HOST";
      // prepend to body to be visible on all pages regardless of template
      (document.body || document.documentElement).prepend(host);
      console.info("[VSP][fillreal] mounted host");
      return host;
    }catch(e){
      try{ console.warn("[VSP][fillreal] mount fail", e); }catch(_){}
      return null;
    }
  };
'''
if needle not in s:
    raise SystemExit("[ERR] cannot find style append anchor in JS")
s = s.replace(needle, ins, 1)

# ensure later code uses mount host if it references any container
# (light-touch: add a host variable and use it as default root)
s = s.replace("const $ = (q, root=document) => root.querySelector(q);",
              "const $ = (q, root=document) => root.querySelector(q);\n  const __vsp_host = __vsp_mount_root();\n", 1)

# add marker
s = s.replace("/* VSP_FILL_REAL_DATA_5TABS_P1_V1 */",
              "/* VSP_FILL_REAL_DATA_5TABS_P1_V1 */\n/* "+MARK+" */", 1)

p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY
