#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_ridnorm_${TS}"
echo "[BACKUP] ${B}.bak_ridnorm_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_BUNDLE_RID_NORMALIZE_V1"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

shim = r"""/* VSP_P0_BUNDLE_RID_NORMALIZE_V1
 * Normalize RID variants: VSP_CI_RUN_YYYYmmdd_HHMMSS -> VSP_CI_YYYYmmdd_HHMMSS
 * Also normalize gate_root_* accordingly.
 */
(()=> {
  if (window.__vsp_p0_bundle_rid_normalize_v1) return;
  window.__vsp_p0_bundle_rid_normalize_v1 = true;

  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (!_fetch) return;

  function normRidStr(x){
    try{
      let t = String(x||"");
      t = t.replace("VSP_CI_RUN_", "VSP_CI_").replace("_RUN_", "_");
      t = t.replace("gate_root_VSP_CI_RUN_", "gate_root_VSP_CI_");
      t = t.replace("gate_root_VSP_CI_", "gate_root_VSP_CI_"); // idempotent
      return t;
    }catch(e){ return x; }
  }

  function rewriteUrl(u){
    try{
      const url = String(u||"");
      // normalize any embedded rid/gate_root text in URL
      return normRidStr(url);
    }catch(e){
      return u;
    }
  }

  window.fetch = function(input, init){
    if (typeof input === "string") {
      return _fetch(rewriteUrl(input), init);
    }
    if (input && typeof input === "object" && input.url) {
      try {
        const nu = rewriteUrl(input.url);
        if (nu !== input.url) input = new Request(nu, input);
      } catch (e) {}
    }
    return _fetch(input, init);
  };
})();
"""

# Put shim at very top so it runs before other bundle code
p.write_text(shim + "\n" + s, encoding="utf-8")
print("[OK] injected:", marker)
PY

node --check "$B" >/dev/null 2>&1 && echo "[OK] node syntax OK" || { echo "[ERR] node syntax FAIL"; exit 2; }
echo "[DONE] Ctrl+Shift+R /vsp5"
