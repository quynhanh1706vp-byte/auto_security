#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need grep; need head

JS1="static/js/vsp_bundle_tabs5_v1.js"
JS2="static/js/vsp_tabs4_autorid_v1.js"

[ -f "$JS1" ] || { echo "[ERR] missing $JS1"; exit 2; }
[ -f "$JS2" ] || { echo "[ERR] missing $JS2"; exit 2; }

echo "== [1] Patch: block luxe loader outside /vsp5 + remove luxe script tags on non-vsp5 =="
python3 - <<'PY'
from pathlib import Path
import time, re

ts=time.strftime("%Y%m%d_%H%M%S")
files=[Path("static/js/vsp_bundle_tabs5_v1.js"), Path("static/js/vsp_tabs4_autorid_v1.js")]

GUARD = r'''
// === CIO: hard-block luxe outside /vsp5 (AUTO) ===
(function(){
  try{
    if (location && location.pathname && location.pathname !== "/vsp5") {
      // remove any luxe script tag if already present
      document.querySelectorAll('script[src*="vsp_dashboard_luxe_v1.js"]').forEach(s=>{ try{s.remove();}catch(e){} });
      // block future injection attempts
      const _origAppend = Element.prototype.appendChild;
      Element.prototype.appendChild = function(node){
        try{
          if (node && node.tagName === "SCRIPT" && node.src && node.src.includes("vsp_dashboard_luxe_v1.js")) {
            return node; // drop
          }
        }catch(e){}
        return _origAppend.call(this, node);
      };
    }
  }catch(e){}
})();
 // === END CIO hard-block luxe ===
'''.strip("\n") + "\n"

for p in files:
    s=p.read_text(encoding="utf-8", errors="replace")
    if "CIO: hard-block luxe outside /vsp5" in s:
        print("[SKIP] already patched:", p.name)
        continue
    bak=p.with_name(p.name+f".bak_blockluxe_{ts}")
    bak.write_text(s, encoding="utf-8")
    # prepend guard at top (before anything runs)
    p.write_text(GUARD + s, encoding="utf-8")
    print("[OK] patched:", p.name, "backup:", bak.name)
PY

echo "== [2] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [3] Re-check HTML references (luxe should still be referenced only on /vsp5; even if referenced elsewhere, JS will remove/stop it) =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "== $p =="
  curl -fsS --max-time 3 --range 0-200000 "$BASE$p" \
    | grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' \
    | head -n 40
done

echo
echo "[DONE] Ctrl+Shift+R. Then open /data_source + /settings and confirm no luxe JS loaded in Network (filter: luxe)."
