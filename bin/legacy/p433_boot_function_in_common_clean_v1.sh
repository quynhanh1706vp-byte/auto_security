#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_c_common_clean_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_p433_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_c_common_clean_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P433_BOOT_FUNCTION_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

boot = r"""
;(()=>{ 
  // VSP_P433_BOOT_FUNCTION_V1
  if (typeof window.boot === "function") return;

  const q = [];
  function run(){
    while(q.length){
      const fn = q.shift();
      try{ fn && fn(); }catch(e){ console.error("[boot]", e); }
    }
  }

  function bootFn(fn){
    if (typeof fn === "function"){
      if (document.readyState === "loading") q.push(fn);
      else { try{ fn(); }catch(e){ console.error("[boot]", e); } }
    }
    return bootFn;
  }
  bootFn.q = q;
  bootFn.run = run;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run, { once:true });
  } else {
    setTimeout(run, 0);
  }
  window.boot = bootFn;
})(); 
"""

# chèn lên đầu file (trước mọi thứ)
p.write_text(boot + "\n" + s, encoding="utf-8")
print("[OK] patched boot() into", p)
PY

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"
