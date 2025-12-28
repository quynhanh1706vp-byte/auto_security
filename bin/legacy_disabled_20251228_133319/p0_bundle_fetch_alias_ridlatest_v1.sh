#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_aliasrid_${TS}"
echo "[BACKUP] ${B}.bak_aliasrid_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_BUNDLE_FETCH_ALIAS_RIDLATEST_V1"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

shim = r"""/* VSP_P0_BUNDLE_FETCH_ALIAS_RIDLATEST_V1 */
(()=> {
  if (window.__vsp_p0_bundle_fetch_alias_ridlatest_v1) return;
  window.__vsp_p0_bundle_fetch_alias_ridlatest_v1 = true;
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (!_fetch) return;

  function rw(u){
    const url = String(u||"");
    if (/\/api\/vsp\/rid_latest(\?|$)/.test(url) || /\/api\/vsp\/latest_rid(\?|$)/.test(url)) {
      return url.replace(/\/api\/vsp\/(rid_latest|latest_rid)(\?|$)/, "/api/vsp/rid_latest_gate_root$2");
    }
    if (url.includes("/api/vsp/rid_latest_gate_root_gate_root")) {
      return url.replace("/api/vsp/rid_latest_gate_root_gate_root", "/api/vsp/rid_latest_gate_root");
    }
    return url;
  }

  window.fetch = function(input, init){
    if (typeof input === "string") return _fetch(rw(input), init);
    if (input && typeof input === "object" && input.url) {
      try { const nu = rw(input.url); if (nu !== input.url) input = new Request(nu, input); } catch(e){}
    }
    return _fetch(input, init);
  };
})();
"""

p.write_text(shim + "\n" + s, encoding="utf-8")
print("[OK] injected:", marker)
PY

node --check "$B" >/dev/null 2>&1 && echo "[OK] node syntax OK" || { echo "[ERR] node syntax FAIL"; exit 2; }
echo "[DONE] Ctrl+Shift+R /vsp5"
