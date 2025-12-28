#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

FILES=(
  static/js/vsp_bundle_tabs5_v1.js
  static/js/vsp_topbar_commercial_v1.js
)
TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || err "missing $f"
  cp -f "$f" "${f}.bak_v1n7_${TS}"
  ok "backup: ${f}.bak_v1n7_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

# 1) Ensure global single-flight helper in bundle
bundle = Path("static/js/vsp_bundle_tabs5_v1.js")
s = bundle.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_SINGLEFLIGHT_HELPER_V1N7"
if MARK not in s:
    helper = r'''
/* ===================== VSP_P0_SINGLEFLIGHT_HELPER_V1N7 =====================
   window.__vspSF(url, ttlMs): single-flight + TTL JSON cache for hot endpoints.
============================================================================ */
(function(){
  try{
    if (window.__VSP_SF_V1N7__) return;
    window.__VSP_SF_V1N7__ = true;
    const inflight = new Map(); // url -> Promise
    const cache = new Map();    // url -> { exp, val }
    function now(){ return Date.now(); }
    window.__vspSF = async function(url, ttlMs){
      const ttl = Math.max(0, Number(ttlMs||0));
      const key = String(url||"");
      const c = cache.get(key);
      if (c && c.exp > now()) return c.val;
      const inf = inflight.get(key);
      if (inf) return await inf;
      const prom = (async ()=>{
        const r = await fetch(key, { credentials:"same-origin" });
        if (!r.ok) throw new Error("HTTP "+r.status+" for "+key);
        const j = await r.json();
        if (ttl) cache.set(key, { exp: now()+ttl, val: j });
        return j;
      })().finally(()=>{ try{ inflight.delete(key); }catch(e){} });
      inflight.set(key, prom);
      return await prom;
    };
  }catch(e){}
})(); 
/* ===================== /VSP_P0_SINGLEFLIGHT_HELPER_V1N7 ===================== */
'''
    # inject after V1N5B block end (stable place)
    m=re.search(r'/\* ===================== /VSP_P0_FE_REQ_COUNTER_V1N5B .*?\*/', s, flags=re.S)
    if m:
      s = s[:m.end()] + "\n\n" + helper + "\n\n" + s[m.end():]
    else:
      s = helper + "\n\n" + s
    bundle.write_text(s, encoding="utf-8")
    print("[OK] injected helper into bundle")
else:
    print("[OK] helper already present")

# 2) Patch topbar to use __vspSF for release_latest + runs?limit=1
top = Path("static/js/vsp_topbar_commercial_v1.js")
t = top.read_text(encoding="utf-8", errors="ignore")
MARK2="VSP_P0_SINGLEFLIGHT_TOPBAR_V1N7"
if MARK2 not in t:
    # Replace fetchJson("/api/vsp/release_latest") variants
    t2 = t
    t2 = re.sub(r'fetch(Json|JSON)\(\s*api\("(/api/vsp/release_latest[^"]*)"\)\s*\)',
                r'__vspSF(api("\2"), 60000)', t2)
    t2 = re.sub(r'fetch\(\s*api\("(/api/vsp/release_latest[^"]*)"\)[^)]*\)\s*\.then\(\s*r\s*=>\s*r\.json\(\)\s*\)',
                r'__vspSF(api("\1"), 60000)', t2)
    # runs?limit=1
    t2 = re.sub(r'fetch(Json|JSON)\(\s*api\("(/api/vsp/runs\?limit=1[^"]*)"\)\s*\)',
                r'__vspSF(api("\2"), 30000)', t2)
    if t2 == t:
        # still add marker; maybe different code path, but safe.
        t2 = "/* %s */\n"%MARK2 + t
    else:
        t2 = "/* %s */\n"%MARK2 + t2
    top.write_text(t2, encoding="utf-8")
    print("[OK] patched topbar")
else:
    print("[OK] topbar already patched")
PY

for f in "${FILES[@]}"; do
  node --check "$f" && ok "node --check OK: $f" || { cp -f "${f}.bak_v1n7_${TS}" "$f"; err "rolled back $f"; }
done

echo "== [DONE] Reload /vsp5 (Ctrl+F5). release_latest + runs?limit=1 should be single-flight+TTL now. =="
