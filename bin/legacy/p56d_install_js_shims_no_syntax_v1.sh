#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

write_shim(){
  local f="$1"
  mkdir -p "$(dirname "$f")"
  cp -f "$f" "${f}.bak_p56d_${TS}" 2>/dev/null || true
  cat > "$f" <<'JS'
/* P56D SHIM: prevent hard JS crash (SyntaxError) - safe no-op fallback */
(function(){
  try{
    window.__VSP_SHIM__ = window.__VSP_SHIM__ || {};
    // minimal helpers
    window.__vspSafe = window.__vspSafe || function(fn){ try{ return fn(); }catch(e){ console.warn("[VSP shim]", e); } };
  }catch(e){}
})();
JS
  node --check "$f" >/dev/null
  echo "[OK] shimmed $f"
}

# create specialized shims
shim_autorid(){
  local f="static/js/vsp_tabs4_autorid_v1.js"
  cp -f "$f" "${f}.bak_p56d_${TS}" 2>/dev/null || true
  cat > "$f" <<'JS'
/* P56D SHIM autorid: keep UI alive */
(function(){
  function getRid(){
    try{
      const u=new URL(location.href);
      return u.searchParams.get("rid")||"";
    }catch(e){ return ""; }
  }
  window.__VSP_AUTORID_V1__ = {
    getRid,
    apply: function(){ /* no-op */ },
  };
  // expose a common function name if older code calls it
  window.__vspAutoRidTry = function(){ return getRid(); };
})();
JS
  node --check "$f" >/dev/null
  echo "[OK] shimmed $f"
}

shim_luxe(){
  local f="static/js/vsp_dashboard_luxe_v1.js"
  cp -f "$f" "${f}.bak_p56d_${TS}" 2>/dev/null || true
  cat > "$f" <<'JS'
/* P56D SHIM luxe: dashboard fallback renderer */
(function(){
  window.__VSP_DASH_LUXE__ = {
    boot: function(){
      // do nothing; real renderer can be restored later
      console.info("[VSP] luxe shim boot");
    }
  };
})();
JS
  node --check "$f" >/dev/null
  echo "[OK] shimmed $f"
}

shim_consistency(){
  local f="static/js/vsp_dashboard_consistency_patch_v1.js"
  cp -f "$f" "${f}.bak_p56d_${TS}" 2>/dev/null || true
  cat > "$f" <<'JS'
/* P56D SHIM consistency patch: no-op */
(function(){
  window.__VSP_DASH_CONSISTENCY_PATCH__ = { apply:function(){} };
})();
JS
  node --check "$f" >/dev/null
  echo "[OK] shimmed $f"
}

shim_autorid
shim_luxe
shim_consistency

echo "[DONE] P56D installed shims. Hard refresh (Ctrl+Shift+R)."
