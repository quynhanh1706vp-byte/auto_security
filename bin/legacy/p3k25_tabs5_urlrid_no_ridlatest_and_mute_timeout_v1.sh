#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_p3k25_${TS}"
echo "[BACKUP] ${F}.bak_p3k25_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3K25_URLRID_NO_RIDLATEST_AND_MUTE_TIMEOUT_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

shim = r'''/* === VSP_P3K25_URLRID_NO_RIDLATEST_AND_MUTE_TIMEOUT_V1 ===
   Commercial rule:
   - If URL has ?rid= => never call /api/vsp/rid_latest* (use URL rid)
   - Mute only timeout/network noise in Firefox (prevent default unhandledrejection logging)
*/
(function(){
  if (window.__VSP_P3K25_SHIM) return;
  window.__VSP_P3K25_SHIM = 1;

  function _urlRid(){
    try{
      var u = new URL(window.location.href);
      var rid = u.searchParams.get("rid") || "";
      return (rid || "").trim();
    }catch(_){ return ""; }
  }

  function _isNoise(x){
    var m = "";
    try{
      if (!x) m = "";
      else if (typeof x === "string") m = x;
      else if (x.reason) m = String(x.reason);
      else if (x.error) m = String(x.error);
      else if (x.message) m = String(x.message);
      else m = String(x);
    }catch(_){ m = ""; }
    m = (m || "").toLowerCase();
    return (
      m.indexOf("timeout") >= 0 ||
      m.indexOf("networkerror") >= 0 ||
      m.indexOf("failed to fetch") >= 0 ||
      m.indexOf("ns_binding_aborted") >= 0 ||
      m.indexOf("connection") >= 0
    );
  }

  window.addEventListener("unhandledrejection", function(ev){
    if (_isNoise(ev)) { try{ ev.preventDefault(); }catch(_){} }
  });

  // fetch shim: if URL rid exists, short-circuit rid_latest calls
  var rid = _urlRid();
  if (!rid) return;

  var _origFetch = window.fetch;
  if (typeof _origFetch === "function" && !window.__VSP_P3K25_FETCH_WRAP){
    window.__VSP_P3K25_FETCH_WRAP = 1;
    window.fetch = function(input, init){
      try{
        var url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        url = String(url || "");
        if (url.indexOf("/api/vsp/rid_latest") >= 0 || url.indexOf("/api/vsp/rid_latest_gate_root") >= 0){
          var body = JSON.stringify({ok:true, rid: rid, mode:"url_rid"});
          return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json"}}));
        }
      }catch(_){}
      return _origFetch.apply(this, arguments);
    };
  }
})();\n
'''

p.write_text(shim + s, encoding="utf-8")
print("[OK] injected shim")
PY

echo "== node -c =="
node -c "$F" && echo "[OK] node -c passed"

echo "== restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" >/dev/null 2>&1 || true
  systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "[DONE] p3k25_tabs5_urlrid_no_ridlatest_and_mute_timeout_v1"
