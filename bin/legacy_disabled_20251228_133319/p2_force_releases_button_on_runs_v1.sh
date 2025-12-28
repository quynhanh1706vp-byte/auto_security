#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

JS="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

MARK="VSP_P2_RELEASES_FAB_ON_RUNS_V1"
if grep -q "$MARK" "$JS"; then
  echo "[OK] already patched: $MARK"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releasesfab_${TS}"
echo "[BACKUP] ${JS}.bak_releasesfab_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="ignore")

snippet = r'''
// VSP_P2_RELEASES_FAB_ON_RUNS_V1
(function(){
  function add(){
    try{
      if (!location || !location.pathname) return;
      if (location.pathname !== "/runs") return;
      if (document.getElementById("vsp-releases-fab")) return;

      var b = document.createElement("button");
      b.id = "vsp-releases-fab";
      b.textContent = "Releases";
      b.setAttribute("type","button");

      b.style.position = "fixed";
      b.style.right = "18px";
      b.style.bottom = "18px";
      b.style.zIndex = "999999";
      b.style.padding = "10px 14px";
      b.style.borderRadius = "14px";
      b.style.border = "1px solid rgba(255,255,255,0.16)";
      b.style.background = "rgba(20,20,26,0.92)";
      b.style.color = "#fff";
      b.style.cursor = "pointer";
      b.style.boxShadow = "0 10px 30px rgba(0,0,0,0.45)";
      b.style.backdropFilter = "blur(6px)";

      b.onmouseenter = function(){ b.style.transform = "translateY(-1px)"; };
      b.onmouseleave = function(){ b.style.transform = ""; };
      b.onclick = function(){ window.location.href = "/releases"; };

      (document.body || document.documentElement).appendChild(b);
    }catch(e){
      try{ console.warn("[VSP] releases fab add failed", e); }catch(_){}
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", add);
  else add();

  window.addEventListener("popstate", add);
})();
'''

# append safely
s2 = s + ("\n" if not s.endswith("\n") else "") + snippet
p.write_text(s2, encoding="utf-8")
print("[OK] patched marker appended")
PY

echo "[OK] done. Now open /runs and Ctrl+Shift+R"
