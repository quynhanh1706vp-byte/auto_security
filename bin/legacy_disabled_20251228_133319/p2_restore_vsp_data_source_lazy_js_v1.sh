#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need mkdir; need cat; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_data_source_lazy_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

mkdir -p static/js
[ -f "$JS" ] && cp -f "$JS" "${JS}.bak_restore_${TS}" && echo "[BACKUP] ${JS}.bak_restore_${TS}" || true

cat > "$JS" <<'JS'
/* VSP_P2_RESTORE_DATA_SOURCE_LAZY_V1
   Purpose: avoid MIME error when page references this script.
   This file is allowed to be a thin shim; real logic may live in vsp_data_source_tab_v3.js etc.
*/
(function(){
  try{
    console.log("[VSP][DATA_SOURCE_LAZY] shim loaded");
    // If the newer tab module exists, optionally call an init hook
    if(window.VSP_DATA_SOURCE && typeof window.VSP_DATA_SOURCE.init === "function"){
      window.VSP_DATA_SOURCE.init();
    }
  }catch(e){}
})();
JS

echo "== verify server serves it as JS =="
curl -sSI "$BASE/static/js/vsp_data_source_lazy_v1.js?v=$(date +%s)" | egrep -i 'HTTP/|content-type' || true
echo "[DONE] Now hard refresh /data_source (Ctrl+Shift+R)"
