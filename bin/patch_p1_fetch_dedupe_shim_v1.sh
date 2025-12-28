#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fetch_dedupe_${TS}" && echo "[BACKUP] $F.bak_fetch_dedupe_${TS}"

# remove old block if exists
perl -0777 -i -pe 's@/\*\s*VSP_FETCH_DEDUPE_SHIM_P1_V1_BEGIN\s*\*/.*?/\*\s*VSP_FETCH_DEDUPE_SHIM_P1_V1_END\s*\*/@@sg' "$F"

cat >> "$F" <<'JS'

/* VSP_FETCH_DEDUPE_SHIM_P1_V1_BEGIN */
(function(){
  'use strict';
  if (window.__VSP_FETCH_DEDUPE_SHIM_P1_V1) return;
  window.__VSP_FETCH_DEDUPE_SHIM_P1_V1 = true;

  const origFetch = window.fetch ? window.fetch.bind(window) : null;
  if (!origFetch) return;

  const cache = new Map();     // url -> {status, ctype, body}
  const inflight = new Map();  // url -> Promise<{status,ctype,body}>

  function urlOf(input){
    try { return (typeof input === "string") ? input : (input && input.url) ? input.url : ""; }
    catch(_e){ return ""; }
  }

  function shouldCache(url){
    if (!url) return false;
    if (url.includes("__nocache=1")) return false;
    // cache/dedupe only the noisy + safe GET JSON endpoints
    return (
      url.includes("/api/vsp/runs_index_v3_fs_resolved") ||
      url.includes("/api/vsp/run_status_v2/") ||
      url.includes("/api/vsp/dashboard_v3")
    );
  }

  function cloneResponseFrom(entry){
    return new Response(entry.body, {
      status: entry.status || 200,
      headers: { "Content-Type": entry.ctype || "application/json" }
    });
  }

  async function fetchAndStore(input, init, url){
    const res = await origFetch(input, init);
    try{
      const c = res.clone();
      const body = await c.text();
      const ctype = c.headers.get("content-type") || "application/json";
      const entry = { status: c.status, ctype, body };
      cache.set(url, entry);
      return entry;
    }catch(_e){
      // if clone fails, don't cache
      return null;
    }
  }

  window.fetch = function(input, init){
    const url = urlOf(input);
    const method = (init && init.method) ? String(init.method).toUpperCase() : "GET";
    if (method !== "GET" || !shouldCache(url)) {
      return origFetch(input, init);
    }

    if (cache.has(url)) {
      return Promise.resolve(cloneResponseFrom(cache.get(url)));
    }

    if (inflight.has(url)) {
      return inflight.get(url).then(entry => entry ? cloneResponseFrom(entry) : origFetch(input, init));
    }

    const p = fetchAndStore(input, init, url)
      .finally(() => inflight.delete(url));

    inflight.set(url, p);

    return origFetch(input, init); // return real response for first caller
  };

  console.log("[VSP_FETCH_DEDUPE_SHIM_P1_V1] enabled");
})();
/* VSP_FETCH_DEDUPE_SHIM_P1_V1_END */

JS

node --check "$F" >/dev/null && echo "[OK] dedupe shim JS syntax OK"
echo "[DONE] fetch dedupe shim appended to $F. Hard refresh Ctrl+Shift+R."
