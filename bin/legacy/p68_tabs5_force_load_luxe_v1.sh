#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p68_${TS}"
echo "[OK] backup ${F}.bak_p68_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P68_FORCE_LOAD_LUXE_V1"
if marker in s:
    print("[OK] already patched P68")
    raise SystemExit(0)

inject=r"""
/* VSP_P68_FORCE_LOAD_LUXE_V1
 * Ensure /vsp5 always loads dashboard luxe JS (prevents blank dashboard due to missing script include)
 */
(function(){
  function ensureLuxe(){
    try{
      if (window.__VSP_P68_LUXE_DONE) return;
      window.__VSP_P68_LUXE_DONE = true;

      // only do this if dashboard container exists
      var host = document.getElementById("vsp-dashboard-main") || document.getElementById("vsp5_root");
      if (!host) return;

      // already present?
      var scripts = Array.prototype.slice.call(document.scripts || []);
      var has = scripts.some(function(sc){ return (sc && sc.src && sc.src.indexOf("vsp_dashboard_luxe_v1.js") >= 0); });
      if (has) { console.info("[VSP] luxe already present (P68)"); return; }

      var sc = document.createElement("script");
      sc.src = "/static/js/vsp_dashboard_luxe_v1.js?v=" + Date.now();
      sc.async = true;
      sc.onload = function(){ console.info("[VSP] luxe loaded (P68)"); };
      sc.onerror = function(e){ console.warn("[VSP] luxe load FAILED (P68)", e); };
      document.head.appendChild(sc);
    }catch(e){}
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ensureLuxe, {once:true});
  } else {
    ensureLuxe();
  }
})();
"""

# Append near end
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched P68 force-load luxe into tabs5 bundle")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P68 applied. Hard refresh: Ctrl+Shift+R"
