#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

FILES=(
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_rid_switch_refresh_all_v1.js
)

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || err "missing $f"
  cp -f "$f" "${f}.bak_v1n6_${TS}"
  ok "backup: ${f}.bak_v1n6_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

def patch_file(path: Path):
    s = path.read_text(encoding="utf-8", errors="ignore")
    MARK="VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6"
    if MARK in s:
        print("[OK] already patched:", path)
        return

    guard = r'''
/* ===================== VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 =====================
   - If rid present in URL or localStorage: never call rid_latest / rid_latest_gate_root
   - Provide shared helpers for rid resolution (stateless-first)
=============================================================================== */
(function(){
  try{
    if (window.__VSP_RID_GUARD_V1N6__) return;
    window.__VSP_RID_GUARD_V1N6__ = true;

    window.__vspGetRidFromUrl = function(){
      try{ return (new URL(location.href)).searchParams.get("rid") || ""; }catch(e){ return ""; }
    };
    window.__vspGetRidFromLS = function(){
      try{ return localStorage.getItem("vsp_rid") || localStorage.getItem("VSP_RID") || ""; }catch(e){ return ""; }
    };
    window.__vspHasUserRid = function(){
      const u = window.__vspGetRidFromUrl();
      const l = window.__vspGetRidFromLS();
      return !!(u || l);
    };
    window.__vspResolveRidFast = function(){
      const u = window.__vspGetRidFromUrl();
      if (u) return u;
      const l = window.__vspGetRidFromLS();
      if (l) return l;
      return "";
    };
    window.__vspBlockHotRidEndpoints = function(url){
      try{
        const u = new URL(String(url), location.origin);
        if (u.origin !== location.origin) return false;
        const p = u.pathname || "";
        if ((p === "/api/vsp/rid_latest" || p === "/api/vsp/rid_latest_gate_root") && window.__vspHasUserRid()){
          return true;
        }
      }catch(e){}
      return false;
    };
  }catch(e){}
})();
 /* ===================== /VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 ===================== */
'''

    # inject at top
    s2 = guard + "\n" + s

    # Patch fetchJson / fetch calls that hit rid_latest* to be conditional
    # Replace direct string occurrences to wrapped function that returns cached/empty
    # (Keep lightweight, no brittle AST)
    s2 = s2.replace('/api/vsp/rid_latest_gate_root', '/api/vsp/rid_latest_gate_root')  # noop marker

    # Add a safe fetch wrapper (only once per file)
    if "__vspFetchJsonGuardV1N6" not in s2:
        s2 += r'''

// VSP_P0_STATELESS_RID_NOHOTCALLS_V1N6 helper
async function __vspFetchJsonGuardV1N6(url){
  if (window.__vspBlockHotRidEndpoints && window.__vspBlockHotRidEndpoints(url)){
    // Return a synthetic response consistent enough for callers to proceed.
    // Prefer rid from URL/LS.
    const rid = (window.__vspResolveRidFast && window.__vspResolveRidFast()) || "";
    return { ok:true, rid: rid, blocked:true };
  }
  const r = await fetch(url, { credentials: "same-origin" });
  if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
  return await r.json();
}
'''

    # Heuristic replace: common patterns used in your codebase
    s2 = re.sub(r'fetchJSON\(\s*api\("(/api/vsp/rid_latest_gate_root[^"]*)"\)\s*\)',
                r'__vspFetchJsonGuardV1N6(api("\1"))', s2)
    s2 = re.sub(r'fetchJSON\(\s*api\("(/api/vsp/rid_latest[^"]*)"\)\s*\)',
                r'__vspFetchJsonGuardV1N6(api("\1"))', s2)
    s2 = re.sub(r'fetchJson\(\s*api\("(/api/vsp/rid_latest_gate_root[^"]*)"\)\s*\)',
                r'__vspFetchJsonGuardV1N6(api("\1"))', s2)
    s2 = re.sub(r'fetchJson\(\s*api\("(/api/vsp/rid_latest[^"]*)"\)\s*\)',
                r'__vspFetchJsonGuardV1N6(api("\1"))', s2)

    path.write_text(s2, encoding="utf-8")
    print("[OK] patched:", path)

for fp in ["static/js/vsp_tabs4_autorid_v1.js","static/js/vsp_rid_switch_refresh_all_v1.js"]:
    patch_file(Path(fp))
PY

for f in "${FILES[@]}"; do
  node --check "$f" && ok "node --check OK: $f" || { warn "node --check FAIL: rollback $f"; cp -f "${f}.bak_v1n6_${TS}" "$f"; err "rolled back $f"; }
done

echo "== [DONE] Reload /vsp5?rid=... (Ctrl+F5). Expect rid_latest* calls to stop when rid is present. =="
