#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p67_${TS}"
echo "[OK] backup ${F}.bak_p67_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P67_MOUNT_ALIAS_GUARD_V1" in s:
    print("[OK] already patched P67")
    raise SystemExit(0)

inject = r"""
/* VSP_P67_MOUNT_ALIAS_GUARD_V1
 * Goal: prevent blank dashboard by providing mount fallback + alias for missing dashboard ids.
 */
(function(){
  try{
    const CANON = () =>
      document.getElementById("vsp-dashboard-main") ||
      document.getElementById("vsp5_root") ||
      document.body;

    window.__VSP_GET = function(id){
      let el = document.getElementById(id);
      if (!el && id && /dash|dashboard|vsp-dashboard|vsp_dashboard/i.test(String(id))) {
        const host = CANON();
        try{
          const esc = (window.CSS && CSS.escape) ? CSS.escape(String(id)) : String(id).replace(/[^a-zA-Z0-9_\-]/g,"\\$&");
          let alias = host.querySelector("#"+esc);
          if (!alias) {
            alias = document.createElement("div");
            alias.id = String(id);
            host.appendChild(alias);
          }
          el = alias;
        }catch(e){
          el = host;
        }
      }
      return el;
    };

    // If after a moment dashboard is still empty, show a helpful banner instead of pure blank.
    window.addEventListener("DOMContentLoaded", function(){
      setTimeout(function(){
        try{
          const m = document.getElementById("vsp-dashboard-main");
          if (m && m.children && m.children.length === 0) {
            const note = document.createElement("div");
            note.setAttribute("data-vsp-p67-banner","1");
            note.style.padding = "14px 16px";
            note.style.margin = "10px 0";
            note.style.border = "1px solid rgba(255,255,255,.12)";
            note.style.borderRadius = "10px";
            note.style.background = "rgba(255,255,255,.04)";
            note.style.color = "rgba(255,255,255,.75)";
            note.textContent = "[VSP] Dashboard JS loaded but rendered nothing yet. Open DevTools Console/Network to see fetch/errors.";
            m.appendChild(note);
          }
        }catch(e){}
      }, 1500);
    }, {once:true});
  }catch(e){}
})();
"""

# 1) Inject helper after 'use strict' if present, else at top.
if "use strict" in s:
    s = re.sub(r'("use strict"\s*;)', r'\1\n'+inject, s, count=1)
else:
    s = inject + "\n" + s

# 2) Replace document.getElementById( -> __VSP_GET(  (safe guard: avoid double replace)
#    This ensures any mount lookup uses alias/fallback if the id is missing.
s = s.replace("document.getElementById(", "__VSP_GET(")

p.write_text(s, encoding="utf-8")
print("[OK] patched P67 mount alias + guard")
PY

# quick sanity: JS parse (node is optional)
if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P67 applied. Hard refresh: Ctrl+Shift+R"
