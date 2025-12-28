#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || err "missing $JS"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetchcache_v1n5_${TS}"
ok "backup: ${JS}.bak_fetchcache_v1n5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P0_GLOBAL_FETCH_CACHE_DEDUPE_V1N5"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''/* ===================== VSP_P0_GLOBAL_FETCH_CACHE_DEDUPE_V1N5 =====================
   Goal: reduce XHR spam by dedupe+TTL cache across ALL FE modules (single place).
   - Dedupe inflight identical GETs (same normalized URL)
   - TTL cache hot endpoints (rid_latest, release_latest, runs, dashboard, gate summary, trend, top_findings)
   - Strip noisy ts= and sort query params for stable keys
=============================================================================== */
(function(){
  try{
    if (window.__VSP_FETCHCACHE_V1N5__) return;
    window.__VSP_FETCHCACHE_V1N5__ = true;

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    const now = ()=> Date.now();
    const inflight = new Map(); // key -> Promise(entry)
    const cache = new Map();    // key -> { exp, status, headers, text }

    function normUrl(input){
      try{
        const u = (input instanceof URL) ? input : new URL(String(input), location.origin);
        if (u.origin !== location.origin) return null;

        // strip cache-busters
        u.searchParams.delete("ts");
        u.searchParams.delete("_ts");
        u.searchParams.delete("__ts");

        // sort params for stable key
        const keys = Array.from(u.searchParams.keys()).sort();
        const pairs = [];
        for(const k of keys){
          const vals = u.searchParams.getAll(k);
          for(const v of vals){
            pairs.push([k, v]);
          }
        }
        u.search = "";
        for(const [k,v] of pairs){
          u.searchParams.append(k, v);
        }
        return u.pathname + (u.search ? u.search : "");
      }catch(e){
        return null;
      }
    }

    function ttlFor(pathq){
      try{
        const path = (pathq||"").split("?")[0] || "";
        // HOT endpoints: cap spam hard
        if (path === "/api/vsp/rid_latest") return 30000;
        if (path === "/api/vsp/rid_latest_gate_root") return 30000;
        if (path === "/api/vsp/release_latest") return 60000;
        if (path === "/api/vsp/runs") return 30000;

        if (path === "/api/vsp/dashboard_v3") return 12000;
        if (path === "/api/vsp/run_gate_summary_v1") return 12000;

        if (path === "/api/vsp/trend_v1") return 15000;
        if (path === "/api/vsp/top_findings_v1") return 15000;

        // Findings paging is noisy/variable => do NOT global-cache it by default
        if (path.startsWith("/api/vsp/findings_page_")) return 0;

        return 0;
      }catch(e){ return 0; }
    }

    function headersToObj(h){
      const o = {};
      try{
        if (!h || !h.forEach) return o;
        h.forEach((v,k)=>{ o[k]=v; });
      }catch(e){}
      return o;
    }
    function objToHeaders(o){
      const h = new Headers();
      try{
        for(const k in (o||{})) h.set(k, String(o[k]));
      }catch(e){}
      return h;
    }

    async function fetchAndStore(key, input, init, ttl){
      const r = await _fetch(input, init);
      try{
        const clone = r.clone();
        const text = await clone.text();
        const ent = { exp: now()+ttl, status: r.status, headers: headersToObj(r.headers), text };
        cache.set(key, ent);
        return ent;
      }catch(e){
        // If we can't read body, still don't break callers
        return { exp: now()+ttl, status: r.status, headers: headersToObj(r.headers), text: "" };
      }
    }

    window.fetch = function(input, init){
      try{
        const method = ((init && init.method) ? String(init.method) : "GET").toUpperCase();
        if (method !== "GET") return _fetch(input, init);

        const key = normUrl(input);
        if (!key) return _fetch(input, init);

        const ttl = ttlFor(key);
        if (!ttl) return _fetch(input, init);

        const c = cache.get(key);
        if (c && c.exp > now()){
          // serve from cache
          return Promise.resolve(new Response(c.text, { status: c.status, headers: objToHeaders(c.headers) }));
        }

        const inf = inflight.get(key);
        if (inf){
          return inf.then(ent => new Response(ent.text, { status: ent.status, headers: objToHeaders(ent.headers) }));
        }

        const prom = fetchAndStore(key, input, init, ttl)
          .finally(()=>{ try{ inflight.delete(key); }catch(e){} });
        inflight.set(key, prom);

        // Caller gets real network response (not cached one) to preserve streaming semantics.
        // But to keep it simple and consistent, return a cloned Response built from stored entry.
        return prom.then(ent => new Response(ent.text, { status: ent.status, headers: objToHeaders(ent.headers) }));
      }catch(e){
        return _fetch(input, init);
      }
    };

  }catch(e){}
})(); 
/* ===================== /VSP_P0_GLOBAL_FETCH_CACHE_DEDUPE_V1N5 ===================== */
'''

# Insert near top (after first block comment if any)
m = re.search(r'^\s*/\*.*?\*/\s*\n', s, flags=re.S)
if m:
    s2 = s[:m.end()] + "\n" + inject + "\n" + s[m.end():]
else:
    s2 = inject + "\n\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

node --check "$JS" && ok "node --check OK: $JS" || { warn "node --check FAIL: rollback"; cp -f "${JS}.bak_fetchcache_v1n5_${TS}" "$JS"; err "rolled back"; }

echo "== [DONE] Reload /vsp5 (Ctrl+F5) then re-measure hot endpoints count as before. =="
