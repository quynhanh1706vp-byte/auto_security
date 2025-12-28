#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need grep; need python3

JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releasesfab_${TS}"
echo "[BACKUP] ${JS}.bak_releasesfab_${TS}"

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_RELEASES_BUTTON_RUNS_V1C_FAB"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

addon = r'''
/* VSP_P2_RELEASES_BUTTON_RUNS_V1C_FAB
   Guaranteed visible fallback button for /runs (does not depend on toolbar DOM).
*/
(function(){
  try{
    if(!location || !location.pathname || !location.pathname.startsWith("/runs")) return;

    function ensure(){
      if(document.getElementById("vsp-btn-releases-fab")) return;

      // Try to also add to any obvious topbar container if found
      function addToToolbar(){
        const host = document.querySelector(".vsp-top-actions")
          || document.querySelector(".vsp-toolbar")
          || document.querySelector(".topbar-right")
          || document.querySelector("header");
        if(!host) return false;
        if(document.getElementById("vsp-btn-releases")) return true;

        const b = document.createElement("button");
        b.id = "vsp-btn-releases";
        b.type = "button";
        b.textContent = "Releases";
        b.title = "Open Release Center";
        b.style.cssText = "margin-left:8px;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:inherit;cursor:pointer;font-size:12px";
        b.addEventListener("click", () => window.open("/releases","_blank"));
        host.appendChild(b);
        return true;
      }
      addToToolbar();

      // FAB fallback (always visible)
      const fab = document.createElement("button");
      fab.id = "vsp-btn-releases-fab";
      fab.type = "button";
      fab.textContent = "Releases";
      fab.title = "Open Release Center (/releases)";
      fab.style.cssText =
        "position:fixed; right:18px; bottom:18px; z-index:99999;" +
        "padding:10px 12px; border-radius:999px;" +
        "border:1px solid rgba(255,255,255,.18);" +
        "background:rgba(20,22,28,.85);" +
        "color:#fff; font-size:12px; cursor:pointer;" +
        "box-shadow:0 10px 25px rgba(0,0,0,.35)";
      fab.addEventListener("click", () => window.open("/releases","_blank"));
      document.body.appendChild(fab);
    }

    if(document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", ensure);
    } else {
      ensure();
    }

    // Runs page can rerender: try a few times
    let tries = 0;
    const t = setInterval(() => {
      tries++;
      ensure();
      if(document.getElementById("vsp-btn-releases-fab") || tries >= 30) clearInterval(t);
    }, 400);
  }catch(e){ /* commercial-safe: swallow */ }
})();
'''.strip("\n") + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8", errors="replace")
print("[OK] appended:", MARK, "file=", str(p))
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P2_RELEASES_BUTTON_RUNS_V1C_FAB" "$JS" | head -n 1 && echo "[OK] marker present"
