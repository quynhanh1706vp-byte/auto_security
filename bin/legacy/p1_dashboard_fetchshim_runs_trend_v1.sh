#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_fetchshim_${TS}"
echo "[BACKUP] ${JS}.bak_dash_fetchshim_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_FETCHSHIM_RUNS_LIMIT1_AND_TREND_POINTS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

shim = r'''
/* ===== VSP_P1_DASH_FETCHSHIM_RUNS_LIMIT1_AND_TREND_POINTS_V1 =====
   목적: commercial-safe UI
   - rewrite /api/vsp/runs?limit=1 => /api/vsp/rid_latest (wrap back to old schema)
   - ensure /api/vsp/trend_v1 has at least 1 point (no empty points[] => no spinner hang)
*/
(function(){
  try{
    if (window.__VSP_DASH_FETCHSHIM_V1) return;
    window.__VSP_DASH_FETCHSHIM_V1 = true;

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    function _asUrl(input){
      try{
        if (typeof input === "string") return input;
        if (input && typeof input.url === "string") return input.url;
      }catch(e){}
      return "";
    }

    function _mkJsonResponse(obj, origRes){
      try{
        const headers = new Headers((origRes && origRes.headers) ? origRes.headers : undefined);
        headers.set("Content-Type","application/json; charset=utf-8");
        const body = JSON.stringify(obj);
        return new Response(body, { status: 200, headers });
      }catch(e){
        return new Response(JSON.stringify(obj), { status: 200, headers: { "Content-Type":"application/json; charset=utf-8" }});
      }
    }

    window.fetch = async function(input, init){
      const url = _asUrl(input);

      // (1) runs?limit=1 -> rid_latest wrapped as old runs schema
      try{
        if (url && url.indexOf("/api/vsp/runs?limit=1") >= 0){
          // keep original behavior if caller explicitly wants offset!=0
          if (url.indexOf("offset=") < 0 || url.indexOf("offset=0") >= 0){
            try{
              const ridRes = await _fetch("/api/vsp/rid_latest", init);
              const ridTxt = await ridRes.text();
              let rid = "";
              try{ rid = (JSON.parse(ridTxt)||{}).rid || ""; }catch(e){}
              if (rid){
                const wrapped = {
                  ok: true,
                  total: 1,
                  limit: 1,
                  offset: 0,
                  runs: [{ rid: rid, mtime: Math.floor(Date.now()/1000) }],
                  roots: [],
                  ts: Math.floor(Date.now()/1000),
                  __via__: "VSP_P1_DASH_FETCHSHIM_V1"
                };
                return _mkJsonResponse(wrapped, ridRes);
              }
            }catch(e){}
          }
        }
      }catch(e){}

      // default fetch
      const res = await _fetch(input, init);

      // (2) trend_v1: ensure points non-empty (safe fallback)
      try{
        if (url && url.indexOf("/api/vsp/trend_v1") >= 0){
          const txt = await res.text();
          let j=null;
          try{ j = JSON.parse(txt); }catch(e){ j=null; }
          if (j && typeof j === "object"){
            const pts = Array.isArray(j.points) ? j.points : [];
            if (pts.length === 0){
              const latest = j.latest_run_id || "";
              const total = (typeof j.total_findings === "number") ? j.total_findings : 0;
              j.points = [{
                label: latest ? String(latest) : "latest",
                run_id: latest,
                total_findings: total,
                ts: Date.now(),
                __fallback__: true
              }];
              j.__via__ = "VSP_P1_DASH_FETCHSHIM_V1";
              return _mkJsonResponse(j, res);
            }
          }
          // if not modified, return original by re-wrapping consumed body
          return new Response(txt, { status: res.status, statusText: res.statusText, headers: res.headers });
        }
      }catch(e){
        // if anything fails, let original response pass through
      }

      return res;
    };
  }catch(e){}
})();
'''

# prepend shim at top (safest)
s2 = shim + "\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", p)
PY

echo "[OK] done. Hard refresh (Ctrl+Shift+R): ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5"
echo "[CHECK] marker:"
grep -n "VSP_P1_DASH_FETCHSHIM_RUNS_LIMIT1_AND_TREND_POINTS_V1" -n "$JS" | head -n 3 || true
