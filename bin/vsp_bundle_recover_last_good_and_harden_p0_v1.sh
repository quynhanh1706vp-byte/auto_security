#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== VSP BUNDLE RECOVER + HARDEN (P0 v1) =="
echo "[PWD] $(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"

B="static/js/vsp_bundle_commercial_v1.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

echo "== find last GOOD backup (node --check pass) =="
# collect candidates: current + backups
mapfile -t CANDS < <(
  { ls -1t static/js/vsp_bundle_commercial_v1.js static/js/vsp_bundle_commercial_v1.js.bak* 2>/dev/null || true; } \
  | awk '!seen[$0]++'
)

GOOD=""
for f in "${CANDS[@]}"; do
  [ -f "$f" ] || continue
  if node --check "$f" >/dev/null 2>&1; then
    GOOD="$f"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] cannot find any bundle/backup that passes node --check."
  echo "== current error context =="
  node --check "$B" 2>out_ci/bundle.nodecheck.err || true
  cat out_ci/bundle.nodecheck.err || true
  exit 3
fi

echo "[OK] last good = $GOOD"

if [ "$GOOD" != "$B" ]; then
  cp -f "$B" "$B.bak_before_recover_${TS}" || true
  cp -f "$GOOD" "$B"
  echo "[RESTORE] $B <= $GOOD"
else
  echo "[INFO] current bundle already passes node --check"
fi

# Append hardening footer (idempotent)
python3 - <<'PY'
from pathlib import Path
import datetime

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "/* VSP_COMMERCIAL_HARDENING_P0_V1 */"
if MARK in s:
  print("[OK] hardening already present (skip)")
  raise SystemExit(0)

footer = r'''
/* VSP_COMMERCIAL_HARDENING_P0_V1 */
(function(){
  'use strict';
  try{ window.__VSP_BUNDLE_COMMERCIAL_V1 = true; }catch(_){}

  // console spam filter (once) for "drilldown real impl accepted"
  try{
    if(!window.__VSP_CONSOLE_FILTER_DD_P0){
      window.__VSP_CONSOLE_FILTER_DD_P0 = 1;
      var needle = "drilldown real impl accepted";
      function wrap(k){
        try{
          var orig = console[k];
          if (typeof orig !== "function") return;
          console[k] = function(){
            try{
              var a0 = (arguments && arguments.length) ? String(arguments[0]) : "";
              if (a0 && a0.indexOf(needle) !== -1){
                if (window.__VSP_DD_ACCEPTED_ONCE) return;
                window.__VSP_DD_ACCEPTED_ONCE = 1;
              }
            }catch(_e){}
            return orig.apply(this, arguments);
          };
        }catch(_){}
      }
      ["log","info","debug","warn"].forEach(wrap);
    }
  }catch(_){}

  // single drilldown entrypoint (safe)
  if (typeof window.VSP_DRILLDOWN !== "function") {
    window.VSP_DRILLDOWN = function(intent){
      try{
        try{ localStorage.setItem("vsp_last_drilldown_intent_v1", JSON.stringify(intent||{})); }catch(_){}
        try{
          if (location && typeof location.hash === "string") {
            if (!location.hash.includes("datasource")) location.hash = "#datasource";
          }
        }catch(_){}
        return true;
      }catch(e){ return false; }
    };
  }

  // HARD-LOCK legacy symbols to function (prevents "not a function")
  function dd(intent){ return window.VSP_DRILLDOWN(intent); }
  function hard(name){
    try{
      var f = dd;
      try{
        Object.defineProperty(window, name, { value: f, writable: false, configurable: false });
      }catch(_){
        window[name] = f;
      }
    }catch(_e){}
  }
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2");
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V1");
  hard("VSP_DASH_DRILLDOWN_ARTIFACTS");
})();
'''
p.write_text(s + "\n\n" + footer + "\n", encoding="utf-8")
print("[OK] appended hardening footer")
PY

# Stub loader/router to stop double-init if they are still loaded
stub() {
  local F="$1"; local NAME="$2"
  if [ -f "$F" ]; then
    cp -f "$F" "$F.bak_stub_${TS}" || true
    cat > "$F" <<EOF
/* ${NAME} STUB (COMMERCIAL HARDEN) */
(function(){
  'use strict';
  try{
    if (window && window.__VSP_BUNDLE_COMMERCIAL_V1){
      return; // disable standalone loader/router in commercial mode
    }
  }catch(_){}
})();
EOF
    echo "[OK] stubbed $F"
  fi
}
stub "static/js/vsp_ui_loader_route_v1.js" "VSP_UI_LOADER_ROUTE"
stub "static/js/vsp_tabs_hash_router_v1.js" "VSP_TABS_HASH_ROUTER"

echo "== node --check bundle (after recover+harden) =="
node --check "$B" && echo "[OK] bundle syntax OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
