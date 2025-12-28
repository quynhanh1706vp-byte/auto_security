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
cp -f "$JS" "${JS}.bak_fetchcache_${TS}"
ok "backup: ${JS}.bak_fetchcache_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_FETCH_CACHE_DEDUPE_V1K"
if MARK in s:
  print("[OK] already patched:", MARK)
  raise SystemExit(0)

inject = r'''/* ===================== VSP_P0_FETCH_CACHE_DEDUPE_V1K =====================
   Purpose: reduce XHR spam by caching/deduping a few hot JSON endpoints at FE layer.
   Targets: /api/vsp/rid_latest, /api/vsp/rid_latest_gate_root, /api/vsp/release_latest
   Notes: strips ts= query param; TTL default 30s; dedup in-flight; returns Response(JSON).
========================================================================= */
(function(){
  try{
    if (window.__VSP_FETCH_CACHE_DEDUPE_V1K__) return;
    window.__VSP_FETCH_CACHE_DEDUPE_V1K__ = true;

    const TTL_MS = 30 * 1000;
    const cache = new Map();     // key -> {ts, status, json}
    const inflight = new Map();  // key -> Promise<{status,json}>

    function isSameOrigin(u){
      try{ return (new URL(u, location.origin)).origin === location.origin; }
      catch(e){ return false; }
    }
    function normUrl(u){
      try{
        const url = new URL(u, location.origin);
        if (url.searchParams.has("ts")) url.searchParams.delete("ts");
        return url.pathname + (url.search ? url.search : "");
      }catch(e){
        return String(u||"");
      }
    }
    function shouldCache(u){
      try{
        const url = new URL(u, location.origin);
        const p = url.pathname || "";
        if (!p.startsWith("/api/vsp/")) return false;
        return (
          p === "/api/vsp/rid_latest" ||
          p === "/api/vsp/rid_latest_gate_root" ||
          p === "/api/vsp/release_latest"
        );
      }catch(e){
        return false;
      }
    }
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

    const origFetch = window.fetch.bind(window);
    window.fetch = function(resource, init){
      try{
        const method = ((init && init.method) || (resource && resource.method) || "GET").toUpperCase();
        const urlStr = (typeof resource === "string") ? resource : (resource && resource.url) ? resource.url : String(resource||"");
        if (method !== "GET") return origFetch(resource, init);
        if (!isSameOrigin(urlStr)) return origFetch(resource, init);
        if (!shouldCache(urlStr)) return origFetch(resource, init);

        const key = method + " " + normUrl(urlStr);
        const now = Date.now();

        const hit = cache.get(key);
        if (hit && (now - hit.ts) < TTL_MS){
          return Promise.resolve(makeJsonResp(hit.json, hit.status));
        }

        const inF = inflight.get(key);
        if (inF){
          return inF.then(r => makeJsonResp(r.json, r.status));
        }

        const pReq = origFetch(resource, init)
          .then(async (r) => {
            let j = {};
            try{ j = await r.clone().json(); }catch(e){ j = {}; }
            const pack = { status: r.status || 200, json: j };
            cache.set(key, { ts: Date.now(), status: pack.status, json: pack.json });
            return pack;
          })
          .finally(() => { try{ inflight.delete(key); }catch(e){} });

        inflight.set(key, pReq);
        return pReq.then(pack => makeJsonResp(pack.json, pack.status));
      }catch(e){
        return origFetch(resource, init);
      }
    };
  }catch(e){}
})(); 
/* ===================== /VSP_P0_FETCH_CACHE_DEDUPE_V1K ===================== */
'''

p.write_text(inject + "\n\n" + s, encoding="utf-8")
print("[OK] injected fetch cache into", str(p))
PY

node --check "$JS" && ok "node --check OK: $JS" || err "node --check FAIL: $JS (auto-rollback manually to .bak_fetchcache_*)"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [DONE] Hard refresh /vsp5 (Ctrl+F5). XHR rid_latest/release_latest should drop massively =="
