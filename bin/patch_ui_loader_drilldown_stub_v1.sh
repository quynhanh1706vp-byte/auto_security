#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_loader_route_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_drillstub_${TS}" && echo "[BACKUP] $F.bak_drillstub_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_ui_loader_route_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker = "window.__VSP_UI_ROUTE_LOADER_V1 = 1;"
if marker not in s:
    raise SystemExit("[ERR] cannot find loader marker")

stub = r'''
  // --- commercial hardening: drilldown stubs (avoid patch-chồng overwrite) ---
  (function(){
    try{
      const mk = (name) => {
        if (typeof window[name] !== 'function'){
          // if overwritten by old patches, force reset
          window[name] = function(){
            try{ console.warn('[VSP_STUB]', name, 'called but not implemented'); }catch(_){}
            return false;
          };
        }
      };
      mk('VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2');
      mk('VSP_DASH_DRILLDOWN_ARTIFACTS_P0_V1');
    }catch(_){}
  })();
  // --- end hardening ---
'''

# inject right after marker, only once
if "commercial hardening: drilldown stubs" in s:
    print("[OK] stub already present")
else:
    s = s.replace(marker, marker + "\n" + stub)
    p.write_text(s, encoding="utf-8")
    print("[OK] injected drilldown stubs into route loader")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK"

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "[NEXT] Ctrl+Shift+R, open #dashboard, confirm no TypeError for drilldown."
