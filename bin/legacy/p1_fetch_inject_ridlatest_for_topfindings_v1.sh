#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetchRidInject_${TS}"
echo "[BACKUP] ${JS}.bak_fetchRidInject_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_FETCH_INJECT_RIDLATEST_TOPFINDINGS_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon = r"""
/* ===== VSP_P1_FETCH_INJECT_RIDLATEST_TOPFINDINGS_V1 =====
   Goal: if URL has ?rid=YOUR_RID (or missing), make /api/vsp/top_findings_v1 always receive a real RID.
   - scrub rid=YOUR_RID from location (history.replaceState)
   - wrap fetch(): for /api/vsp/top_findings_v1, inject rid_latest when rid missing/YOUR_RID
*/
(function(){
  try{
    if(window.__VSP_FETCH_RID_INJECTED_V1) return;
    window.__VSP_FETCH_RID_INJECTED_V1 = true;

    // 1) scrub URL rid=YOUR_RID
    (function scrub(){
      try{
        var u = new URL(location.href);
        var rid = (u.searchParams.get("rid") || u.searchParams.get("RID") || "").toString().trim();
        if(rid === "YOUR_RID"){
          u.searchParams.delete("rid");
          u.searchParams.delete("RID");
          history.replaceState(null, "", u.toString());
          try{ window.__VSP_RID = ""; }catch(e){}
        }
      }catch(e){}
    })();

    // 2) cache rid_latest
    var __rid_cache = { rid:"", ts:0 };
    async function getRidLatest(){
      var now = Date.now();
      if(__rid_cache.rid && (now - __rid_cache.ts) < 30000) return __rid_cache.rid;
      try{
        var r = await fetch("/api/vsp/rid_latest", { credentials:"same-origin" });
        var j = await r.json().catch(function(){ return null; });
        var rid = (j && (j.rid || j.RID) || "").toString().trim();
        if(rid && rid !== "YOUR_RID"){
          __rid_cache.rid = rid; __rid_cache.ts = now;
          return rid;
        }
      }catch(e){}
      return __rid_cache.rid || "";
    }

    // 3) wrap fetch for top_findings_v1 only
    var _fetch = window.fetch ? window.fetch.bind(window) : null;
    if(!_fetch) return;

    window.fetch = async function(input, init){
      try{
        var url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        if(url && url.indexOf("/api/vsp/top_findings_v1") >= 0){
          var u = new URL(url, location.origin);
          var rid = (u.searchParams.get("rid") || u.searchParams.get("RID") || "").toString().trim();
          if(!rid || rid === "YOUR_RID"){
            var lr = await getRidLatest();
            if(lr){
              u.searchParams.set("rid", lr);
              if(typeof input === "string"){
                input = u.toString();
              }else{
                // preserve request method/headers by cloning when possible
                try{
                  input = new Request(u.toString(), input);
                }catch(e){
                  input = u.toString();
                }
              }
            }
          }
        }
      }catch(e){}
      return _fetch(input, init);
    };
  }catch(e){}
})();
""".strip()

# append at end
s2 = s.rstrip() + "\n\n" + addon + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R and open: http://127.0.0.1:8910/vsp5 (NO ?rid=YOUR_RID)"
