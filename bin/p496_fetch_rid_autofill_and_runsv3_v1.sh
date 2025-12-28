#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p496_${TS}"
mkdir -p "$OUT"
cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_FETCH_RID_AUTOFILL_AND_RUNSV3_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet=r"""
/* VSP_FETCH_RID_AUTOFILL_AND_RUNSV3_V1:
   - rewrite /api/vsp/runs -> /api/vsp/runs_v3
   - autofill rid when rid is missing/empty using window.VSP_RID or localStorage.VSP_RID
   - learn rid from runs_v3/top_findings responses when possible
*/
(function(){
  try{
    if (window.__VSP_FETCH_PATCHED_V1__) return;
    window.__VSP_FETCH_PATCHED_V1__ = 1;

    function _getRID(){
      try{
        return (window.VSP_RID || localStorage.getItem("VSP_RID") || "").toString().trim();
      }catch(e){ return ""; }
    }

    function _maybeLearnRID(obj){
      try{
        if (!obj) return;
        // common shapes: {rid: "..."} or {items:[{rid:"..."}]} or {runs:[{rid:"..."}]}
        var cand = "";
        if (obj.rid) cand = obj.rid;
        if (!cand && obj.items && obj.items[0] && obj.items[0].rid) cand = obj.items[0].rid;
        if (!cand && obj.runs && obj.runs[0] && obj.runs[0].rid) cand = obj.runs[0].rid;
        if (cand) {
          window.VSP_RID = cand;
          try{ localStorage.setItem("VSP_RID", cand); }catch(e){}
        }
      }catch(e){}
    }

    function _normUrl(url){
      try{
        var u = new URL(url, location.origin);

        // rewrite old runs endpoint
        if (u.pathname === "/api/vsp/runs") u.pathname = "/api/vsp/runs_v3";

        // rid autofill for vsp endpoints when rid empty/missing
        if (u.pathname.startsWith("/api/vsp/")) {
          var rid = u.searchParams.get("rid");
          var needsRid =
            /\/(datasource_v3|data_source_v1|findings_unified_v1|overrides_v1|exports_v1|datasource|overrides|run_status_v1)$/.test(u.pathname);

          if (needsRid && (!rid || rid.trim() === "")) {
            var r = _getRID();
            if (r) u.searchParams.set("rid", r);
          }
        }
        return u.toString();
      }catch(e){
        return url;
      }
    }

    var _fetch = window.fetch;
    if (typeof _fetch === "function") {
      window.fetch = function(input, init){
        try{
          var url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
          var nu = _normUrl(url);

          var p;
          if (typeof input === "string") {
            p = _fetch(nu, init);
          } else if (input && input.url) {
            try{
              var req = new Request(nu, input);
              p = _fetch(req, init);
            }catch(e){
              p = _fetch(input, init);
            }
          } else {
            p = _fetch(input, init);
          }

          // learn RID from JSON responses (best-effort)
          return Promise.resolve(p).then(function(resp){
            try{
              var ct = (resp && resp.headers && resp.headers.get) ? (resp.headers.get("content-type") || "") : "";
              if (ct.indexOf("application/json") >= 0) {
                resp.clone().json().then(_maybeLearnRID).catch(function(){});
              }
            }catch(e){}
            return resp;
          });
        }catch(e){
          return _fetch(input, init);
        }
      };
    }
  }catch(e){}
})();
"""

# Insert after console gate marker if present; else prepend
pos = s.find("VSP_CONSOLE_GATE_V1")
if pos != -1:
    # insert after that block (simple heuristic: after next "})();")
    m = re.search(r"VSP_CONSOLE_GATE_V1[\s\S]{0,2000}?\}\)\(\);\s*", s)
    if m:
        ins = m.end()
        s2 = s[:ins] + "\n" + snippet + "\n" + s[ins:]
    else:
        s2 = snippet + "\n" + s
else:
    s2 = snippet + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[OK] patched fetch rid autofill + runs->runs_v3"
echo "[TIP] learn rid automatically; you can also force: localStorage.VSP_RID='VSP_CI_....'"
