#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs_hash_router_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_normhash_${TS}"
echo "[BACKUP] $F.bak_normhash_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tabs_hash_router_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
TAG="// === VSP_P2_NORMALIZE_TAB_HASH_V1 ==="
if TAG not in t:
    t += "\n" + TAG + r"""
(function(){
  try{
    var h = String(window.location.hash || "");
    var m = h.match(/^#tab=([a-z0-9_-]+)(.*)$/i);
    if(m){
      var tab = m[1];
      var rest = m[2] || "";
      window.location.hash = "#" + tab + rest;
    }
  }catch(e){}
})();
"""
p.write_text(t, encoding="utf-8")
print("[OK] appended normalize-hash")
PY

node --check "$F"
echo "[OK] node --check OK"
