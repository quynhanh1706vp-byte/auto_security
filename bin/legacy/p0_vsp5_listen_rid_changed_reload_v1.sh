#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_dash_only_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_vsp5rid_${TS}"
echo "[BACKUP] ${F}.bak_vsp5rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_VSP5_RID_CHANGED_RELOAD_V1"
if marker in s:
    print("[INFO] already"); raise SystemExit(0)

inject = textwrap.dedent(r"""
/* VSP_VSP5_RID_CHANGED_RELOAD_V1 */
(()=> {
  try{
    if (window.__vsp_vsp5_rid_reload_v1) return;
    window.__vsp_vsp5_rid_reload_v1 = true;

    let t = null;
    function isTyping(){
      const a = document.activeElement;
      if(!a) return false;
      const tag = (a.tagName||"").toLowerCase();
      return tag==="input" || tag==="textarea" || a.isContentEditable;
    }

    window.addEventListener("vsp:rid_changed", ()=>{
      try{
        if (isTyping()) return;
        if (t) clearTimeout(t);
        t = setTimeout(()=>{ location.reload(); }, 250);
      }catch(e){}
    });
  }catch(e){}
})();
""")

m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
if m:
    pos = m.end()
    s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
else:
    s2 = inject + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null && echo "[OK] node --check: $F"
echo "[DONE] Ctrl+F5 /vsp5. When rid changes, vsp5 reloads."
