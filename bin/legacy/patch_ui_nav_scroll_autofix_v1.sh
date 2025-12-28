#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
JSF="static/js/vsp_nav_scroll_autofix_v1.js"

[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

# 1) write JS (idempotent by marker)
mkdir -p "$(dirname "$JSF")"
if [ ! -f "$JSF" ] || ! grep -q "VSP_NAV_SCROLL_AUTOFIX_V1" "$JSF"; then
  cat > "$JSF" <<'JS'
/* VSP_NAV_SCROLL_AUTOFIX_V1: make left nav scrollable even when CSS selector unknown */
(function(){
  function pickNavContainer(anchor){
    // Walk up and find an ancestor that contains multiple nav items (sidebar list)
    let p = anchor;
    for (let i=0; i<20 && p; i++){
      try {
        const items = p.querySelectorAll ? p.querySelectorAll(".vsp-nav-item, a.vsp-tab, a[data-tab]") : [];
        if (items && items.length >= 4) return p;
      } catch(_){}
      p = p.parentElement;
    }
    return null;
  }

  function apply(){
    const tab = document.getElementById("tab-rules");
    if (!tab) return;

    // Ensure it isn't accidentally hidden
    tab.style.display = "";
    tab.style.visibility = "visible";

    const nav = pickNavContainer(tab) || tab.parentElement;
    if (!nav) return;

    // Make scrollable
    nav.style.overflowY = "auto";
    nav.style.maxHeight = "100vh";
    nav.style.webkitOverflowScrolling = "touch";

    // If nav is inside a fixed sidebar, also allow its parent to not clip
    if (nav.parentElement){
      nav.parentElement.style.overflow = "visible";
    }
    console.log("[VSP_NAV_SCROLL_AUTOFIX_V1] applied");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }
  window.addEventListener("hashchange", apply);
})();
JS
  echo "[OK] wrote $JSF"
else
  echo "[OK] $JSF already patched"
fi

# 2) include script in template (idempotent)
grep -q "VSP_NAV_SCROLL_AUTOFIX_V1" "$T" && { echo "[OK] template already includes nav autofix"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_navautofix_${TS}"
echo "[BACKUP] $T.bak_navautofix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
t=Path("templates/vsp_4tabs_commercial_v1.html")
s=t.read_text(encoding="utf-8", errors="replace")

inject = r'''
<!-- VSP_NAV_SCROLL_AUTOFIX_V1 -->
<script src="/static/js/vsp_nav_scroll_autofix_v1.js"></script>
'''

if "VSP_NAV_SCROLL_AUTOFIX_V1" in s:
    print("[OK] already present")
else:
    # place before </body> if possible
    if "</body>" in s:
        s = s.replace("</body>", inject + "\n</body>")
    else:
        s = s + "\n" + inject + "\n"
    t.write_text(s, encoding="utf-8")
    print("[OK] injected nav autofix script into template")
PY

echo "[DONE] patch_ui_nav_scroll_autofix_v1 OK"
