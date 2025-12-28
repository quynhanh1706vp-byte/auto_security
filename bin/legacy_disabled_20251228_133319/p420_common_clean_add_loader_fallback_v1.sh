#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need head; need node; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }

CLEAN="static/js/vsp_c_common_clean_v1.js"
mkdir -p static/js

if [ -f "$CLEAN" ]; then
  cp -f "$CLEAN" "${CLEAN}.bak_${TS}"
  ok "backup existing $CLEAN"
fi

cat > "$CLEAN" <<'JS'
/* VSP_C_COMMON_CLEAN_V1
   - Minimal, safe helpers (no override existing behavior)
   - installOnce registry to stop duplicate installers (P421-ready)
   - log wrappers
*/
(function(){
  'use strict';
  const W = window;
  W.VSP = W.VSP || {};

  // --- logging (prefix, can be silenced by setting VSP_LOG=0) ---
  const LOG_ON = (W.VSP_LOG === undefined) ? 1 : (W.VSP_LOG ? 1 : 0);
  function _pfx(){ return '[VSP]'; }
  W.VSP.log = function(){ if(!LOG_ON) return; try{ console.log(_pfx(), ...arguments); }catch(e){} };
  W.VSP.warn = function(){ if(!LOG_ON) return; try{ console.warn(_pfx(), ...arguments); }catch(e){} };
  W.VSP.err = function(){ if(!LOG_ON) return; try{ console.error(_pfx(), ...arguments); }catch(e){} };

  // --- DOM helpers (non-invasive) ---
  W.VSP.q  = W.VSP.q  || function(sel, root){ return (root||document).querySelector(sel); };
  W.VSP.qa = W.VSP.qa || function(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); };
  W.VSP.on = W.VSP.on || function(el, ev, fn, opt){ if(el && el.addEventListener) el.addEventListener(ev, fn, opt||false); };

  // --- installOnce (idempotent) ---
  const _reg = W.VSP.__install_registry = W.VSP.__install_registry || Object.create(null);
  W.VSP.installOnce = W.VSP.installOnce || function(key, fn){
    try{
      if(_reg[key]) return false;
      _reg[key] = 1;
      fn && fn();
      return true;
    }catch(e){
      try{ W.VSP.err('installOnce failed', key, e); }catch(_) {}
      return false;
    }
  };

  // --- small utils ---
  W.VSP.nowISO = W.VSP.nowISO || function(){ try{ return new Date().toISOString(); }catch(e){ return ''; } };

  // mark loaded
  W.VSP.__c_common_clean_v1 = 1;
})();
JS

node --check "$CLEAN" >/dev/null
ok "created + syntax-ok: $CLEAN"

# Patch templates: insert clean script tag BEFORE vsp_c_common_v1.js include (keep old as fallback)
# We search all templates for 'vsp_c_common_v1.js' and inject line above it if not already present.
python3 - <<'PY'
from pathlib import Path
import re, datetime

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
clean = "/static/js/vsp_c_common_clean_v1.js"
needle = "vsp_c_common_v1.js"

tpls = list(Path("templates").glob("**/*.html"))
patched = 0
for t in tpls:
    s = t.read_text(encoding="utf-8", errors="replace")
    if needle not in s:
        continue
    if clean in s:
        continue
    # inject before first occurrence of vsp_c_common_v1.js script tag
    pat = re.compile(r'(<script[^>]+src=["\']/static/js/[^"\']*vsp_c_common_v1\.js[^"\']*["\'][^>]*>\s*</script>)', re.I)
    m = pat.search(s)
    if not m:
        continue
    inj = f'<script defer src="{clean}"></script>\n' + m.group(1)
    s2 = s[:m.start()] + inj + s[m.end():]
    bak = t.with_suffix(t.suffix + f".bak_p420_{ts}")
    bak.write_text(s, encoding="utf-8")
    t.write_text(s2, encoding="utf-8")
    patched += 1

print("patched_templates=", patched)
PY

# Restart service (best-effort)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC"; then
    ok "restarting $SVC"
    sudo systemctl restart "$SVC"
  else
    warn "service $SVC not active (skip restart)"
  fi
else
  warn "systemctl not found (skip restart)"
fi

# Quick smoke minimal: just hit /vsp5
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/vsp5" >/dev/null
ok "basic GET /vsp5 ok"

# Run full smoke if available
if [ -x bin/p422_smoke_commercial_one_shot_v1.sh ]; then
  ok "run P422 smoke"
  bash bin/p422_smoke_commercial_one_shot_v1.sh
else
  warn "P422 not found, create it first if you want full smoke"
fi

ok "P420 done (clean file loaded before old common; old common remains fallback)"
