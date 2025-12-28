#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p69b_${TS}"
echo "[OK] backup ${F}.bak_p69b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P69B_SAFE_GET_V1" in s:
    print("[OK] already patched P69B")
    raise SystemExit(0)

# 1) First, rewrite calls BEFORE we inject helper (so helper code won't be affected)
# Replace any legacy helper calls too
s = s.replace("__VSP_GET(", "__VSP_GET_SAFE(")
s = s.replace("document.getElementById(", "__VSP_GET_SAFE(")

inject = r"""
/* VSP_P69B_SAFE_GET_V1
 * Fix blank dashboard by using a SAFE DOM getter based on native getElementById (no recursion),
 * plus alias fallback for dashboard containers.
 */
(function(){
  try{
    if (window.__VSP_GET_SAFE) return;

    // Native getElementById (never replaced)
    function nativeGE(id){
      try { return Document.prototype.getElementById.call(document, id); }
      catch(e){ return null; }
    }

    function canonHost(){
      return nativeGE("vsp-dashboard-main") || nativeGE("vsp5_root") || document.body;
    }

    window.__VSP_GET_SAFE = function(id){
      var el = nativeGE(id);
      if (!el && id && /dash|dashboard|vsp-dashboard|vsp_dashboard/i.test(String(id))) {
        var host = canonHost();
        try{
          var esc = (window.CSS && CSS.escape) ? CSS.escape(String(id)) : String(id).replace(/[^a-zA-Z0-9_\-]/g,"\\$&");
          var alias = host.querySelector("#"+esc);
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

    console.info("[VSP] luxe boot marker (P69B)");

    // If still empty after a moment, show a banner (so it won't look dead)
    window.addEventListener("DOMContentLoaded", function(){
      setTimeout(function(){
        try{
          var m = nativeGE("vsp-dashboard-main");
          if (m && m.children && m.children.length === 0 && !m.querySelector("[data-vsp-p69b-banner]")) {
            var note = document.createElement("div");
            note.setAttribute("data-vsp-p69b-banner","1");
            note.style.padding = "14px 16px";
            note.style.margin = "10px 0";
            note.style.border = "1px solid rgba(255,255,255,.12)";
            note.style.borderRadius = "10px";
            note.style.background = "rgba(255,255,255,.04)";
            note.style.color = "rgba(255,255,255,.75)";
            note.textContent = "[VSP] Dashboard JS loaded but rendered nothing yet. Check DevTools Console/Network for errors.";
            m.appendChild(note);
          }
        }catch(e){}
      }, 1500);
    }, {once:true});
  }catch(e){}
})();
"""

# 2) Inject helper near top (after "use strict"; if present)
if '"use strict"' in s:
    s = re.sub(r'("use strict"\s*;)', r'\1\n'+inject, s, count=1)
else:
    s = inject + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] P69B applied: SAFE DOM getter + banner + boot log")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P69B applied. Hard refresh: Ctrl+Shift+R"
