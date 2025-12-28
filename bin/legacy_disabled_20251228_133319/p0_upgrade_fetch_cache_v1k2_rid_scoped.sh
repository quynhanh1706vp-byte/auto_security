#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || err "missing $JS"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetchcache_v1k2_${TS}"
ok "backup: ${JS}.bak_fetchcache_v1k2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_P0_FETCH_CACHE_DEDUPE_V1K2" in s:
  print("[OK] already upgraded to V1K2")
  raise SystemExit(0)

# Replace TTL + shouldCache + normUrl portions inside V1K block (surgical)
# We'll just append a small "upgrade shim" right after V1K block end marker.
ins = r'''
/* ===================== VSP_P0_FETCH_CACHE_DEDUPE_V1K2 =====================
   Upgrade:
   - strip ts= for ALL /api/vsp/*
   - also cache rid-scoped heavy endpoints: dashboard_v3, run_gate_summary_v1 (TTL 12s)
========================================================================= */
(function(){
  try{
    if (!window.__VSP_FETCH_CACHE_DEDUPE_V1K__) return;
    if (window.__VSP_FETCH_CACHE_DEDUPE_V1K2__) return;
    window.__VSP_FETCH_CACHE_DEDUPE_V1K2__ = true;

    const TTL_HEAVY_MS = 12 * 1000;

    // Wrap fetch again but delegate to the already-wrapped fetch cache if present.
    const prevFetch = window.fetch.bind(window);

    function isSameOrigin(u){
      try{ return (new URL(u, location.origin)).origin === location.origin; }
      catch(e){ return false; }
    }
    function stripTsAll(u){
      try{
        const url = new URL(u, location.origin);
        if (url.pathname.startsWith("/api/vsp/") && url.searchParams.has("ts")) url.searchParams.delete("ts");
        return url.pathname + (url.search ? url.search : "");
      }catch(e){ return String(u||""); }
    }
    function isHeavy(u){
      try{
        const url = new URL(u, location.origin);
        if (!url.pathname.startsWith("/api/vsp/")) return false;
        return (url.pathname === "/api/vsp/dashboard_v3" || url.pathname === "/api/vsp/run_gate_summary_v1");
      }catch(e){ return false; }
    }

    const heavyCache = new Map();   // key -> {ts, status, json}
    const heavyIn = new Map();      // key -> Promise

    function makeJsonResp(obj, status){
      try{
        return new Response(JSON.stringify(obj ?? {}), {
          status: status || 200,
          headers: { "Content-Type": "application/json; charset=utf-8" }
        });
      }catch(e){
        return new Response("{}", {status: status || 200, headers: {"Content-Type":"application/json"}});
      }
    }

    window.fetch = function(resource, init){
      try{
        const method = ((init && init.method) || (resource && resource.method) || "GET").toUpperCase();
        const urlStr = (typeof resource === "string") ? resource : (resource && resource.url) ? resource.url : String(resource||"");
        if (method !== "GET") return prevFetch(resource, init);
        if (!isSameOrigin(urlStr)) return prevFetch(resource, init);

        const n = stripTsAll(urlStr);

        // Heavy rid-scoped cache
        if (isHeavy(urlStr)){
          const key = method + " " + n;
          const now = Date.now();
          const hit = heavyCache.get(key);
          if (hit && (now - hit.ts) < TTL_HEAVY_MS){
            return Promise.resolve(makeJsonResp(hit.json, hit.status));
          }
          const infl = heavyIn.get(key);
          if (infl){
            return infl.then(pack => makeJsonResp(pack.json, pack.status));
          }
          const pReq = prevFetch(n, init)
            .then(async (r)=>{
              let j = {};
              try{ j = await r.clone().json(); }catch(e){ j = {}; }
              const pack = {status: r.status || 200, json: j};
              heavyCache.set(key, {ts: Date.now(), status: pack.status, json: pack.json});
              return pack;
            })
            .finally(()=>{ try{ heavyIn.delete(key); }catch(e){} });
          heavyIn.set(key, pReq);
          return pReq.then(pack => makeJsonResp(pack.json, pack.status));
        }

        // For all /api/vsp/* just strip ts and delegate
        if (n !== urlStr && n.startsWith("/api/vsp/")){
          return prevFetch(n, init);
        }

        return prevFetch(resource, init);
      }catch(e){
        return prevFetch(resource, init);
      }
    };
  }catch(e){}
})();
 /* ===================== /VSP_P0_FETCH_CACHE_DEDUPE_V1K2 ===================== */
'''

# Insert right after V1K end marker
marker = "/* ===================== /VSP_P0_FETCH_CACHE_DEDUPE_V1K ===================== */"
idx = s.find(marker)
if idx < 0:
  raise SystemExit("[ERR] cannot find V1K end marker")
idx2 = idx + len(marker)
s2 = s[:idx2] + "\n" + ins + "\n" + s[idx2:]
p.write_text(s2, encoding="utf-8")
print("[OK] upgraded to V1K2:", str(p))
PY

node --check "$JS" && ok "node --check OK: $JS" || err "node --check FAIL: $JS"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [DONE] Reload /vsp5 (Ctrl+F5). Heavy endpoints should be capped. =="
