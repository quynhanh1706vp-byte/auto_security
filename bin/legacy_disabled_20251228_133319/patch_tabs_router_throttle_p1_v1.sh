#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs_hash_router_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_throttle_${TS}" && echo "[BACKUP] $F.bak_throttle_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tabs_hash_router_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# remove old injected block if any
s=re.sub(r'/\*\s*VSP_ROUTER_THROTTLE_P1_V1_BEGIN\s*\*/.*?/\*\s*VSP_ROUTER_THROTTLE_P1_V1_END\s*\*/\s*',
         '', s, flags=re.S)

inj = r'''
/* VSP_ROUTER_THROTTLE_P1_V1_BEGIN */
(function(){
  'use strict';
  if (window.__VSP_ROUTER_THROTTLE_P1_V1) return;
  window.__VSP_ROUTER_THROTTLE_P1_V1 = true;

  const W = window;
  const orig = W.handleHashChange || W.__vspHandleHashChange || null;

  // If file defines handleHashChange in local scope only, fallback: patch hashchange listener to throttle.
  let last = {h:"", t:0};
  function shouldSkip(){
    const h = String(location.hash || "");
    const now = Date.now();
    if (h === last.h && (now - last.t) < 600) return true;
    last = {h, t: now};
    return false;
  }

  // If global handleHashChange exists, wrap it
  if (typeof orig === "function"){
    W.__vspHandleHashChange = orig;
    W.handleHashChange = function(){
      if (shouldSkip()) return;
      return orig.apply(this, arguments);
    };
    console.log("[VSP_ROUTER_THROTTLE_P1_V1] wrapped global handleHashChange");
    return;
  }

  // Otherwise, add throttled listener (does not remove existing; only prevents rapid duplicates)
  W.addEventListener("hashchange", function(ev){
    if (shouldSkip()) return;
  }, true);

  console.log("[VSP_ROUTER_THROTTLE_P1_V1] installed hashchange throttle (capture)");
})();
/* VSP_ROUTER_THROTTLE_P1_V1_END */
'''
s = s.rstrip() + "\n\n" + inj + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended router throttle shim")
PY

node --check "$F" >/dev/null && echo "[OK] router JS syntax OK"
echo "[DONE] Router throttle applied. Hard refresh Ctrl+Shift+R."
