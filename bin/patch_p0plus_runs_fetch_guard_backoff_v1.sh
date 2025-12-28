#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fetchguard_${TS}"
echo "[BACKUP] ${F}.bak_fetchguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_FETCH_GUARD_BACKOFF_P0PLUS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_RUNS_FETCH_GUARD_BACKOFF_P0PLUS_V1 */
(function(){
  try{
    if(window.__VSP_RUNS_FETCH_GUARD__) return;
    window.__VSP_RUNS_FETCH_GUARD__ = 1;

    const origFetch = window.fetch.bind(window);
    let lastGoodText = null;
    let inFlight = null;
    let lastCallAt = 0;
    let failCount = 0;
    let cooldownUntil = 0;

    const MIN_GAP_MS = 1500;
    const TIMEOUT_MS = 4500;

    function isRunsURL(u){
      try{
        if(typeof u !== "string") u = (u && u.url) ? u.url : String(u);
        return u.includes("/api/vsp/runs");
      }catch(e){ return false; }
    }
    function mkRespFromText(txt){
      return new Response(txt, {status: 200, headers: {"Content-Type":"application/json"}});
    }

    window.fetch = async function(input, init){
      if(!isRunsURL(input)) return origFetch(input, init);

      const now = Date.now();

      // cooldown after failures -> serve cache (no spam)
      if(now < cooldownUntil && lastGoodText){
        return mkRespFromText(lastGoodText);
      }

      // prevent overlap
      if(inFlight) return inFlight;

      // spacing
      const wait = Math.max(0, MIN_GAP_MS - (now - lastCallAt));
      if(wait) await new Promise(r=>setTimeout(r, wait));
      lastCallAt = Date.now();

      const ctrl = new AbortController();
      const t = setTimeout(()=>ctrl.abort(), TIMEOUT_MS);

      const doFetch = (async ()=>{
        try{
          const r = await origFetch(input, Object.assign({}, init||{}, {signal: ctrl.signal, cache:"no-store"}));
          clearTimeout(t);

          // cache last good payload
          try{
            if(r && r.ok){
              const clone = r.clone();
              clone.text().then(txt=>{
                if(txt && txt.trim().startsWith("{")) lastGoodText = txt;
              }).catch(()=>{});
              failCount = 0;
              cooldownUntil = 0;
            }
          }catch(e){}

          return r;
        }catch(e){
          clearTimeout(t);
          failCount = Math.min(8, failCount + 1);
          const backoff = Math.min(20000, 700 * Math.pow(2, failCount));
          cooldownUntil = Date.now() + backoff;

          if(lastGoodText){
            return mkRespFromText(lastGoodText);
          }
          throw e;
        }finally{
          inFlight = null;
        }
      })();

      inFlight = doFetch;
      return doFetch;
    };

    console.log("[VSP] runs fetch guard/backoff enabled");
  }catch(e){}
})();
'''.lstrip("\n")

s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK"
echo "[NEXT] restart UI + Ctrl+F5 /vsp5"
