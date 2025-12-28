#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3

JS="static/js/vsp_fetch_guard_rid_v1.js"
mkdir -p static/js

cat > "$JS" <<'JS'
/* VSP_FETCH_GUARD_RID_V1 (v2): patch fetch + XHR, add rid + sane limits */
(function(){
  if (window.__VSP_FETCH_GUARD_RID_V1__ && window.__VSP_FETCH_GUARD_RID_V1__.v2) return;

  function getRid(){
    try{ return (new URL(location.href)).searchParams.get("rid") || ""; }catch(_){ return ""; }
  }
  var RID = (getRid() || "").trim();
  window.__VSP_ACTIVE_RID__ = RID;
  window.__VSP_FETCH_GUARD_RID_V1__ = { ok:true, v2:true, ts:Date.now(), rid:RID };

  function patchUrl(url){
    try{
      if (!RID) return url;
      if (typeof url !== "string") return url;
      if (!url.startsWith("/api/vsp/")) return url;
      if (url.startsWith("/api/vsp/rid_latest")) return url;

      var u = new URL(url, location.origin);

      // force rid if missing
      if (!u.searchParams.get("rid")) u.searchParams.set("rid", RID);

      // sane defaults to avoid huge payloads (esp top_findings)
      if (u.pathname.endsWith("/top_findings_v1")){
        var lim = parseInt(u.searchParams.get("limit") || "0", 10);
        if (!lim || lim > 200) u.searchParams.set("limit","200");
        if (!u.searchParams.get("offset")) u.searchParams.set("offset","0");
      }
      if (u.pathname.endsWith("/trend_v1")){
        var tlim = parseInt(u.searchParams.get("limit") || "0", 10);
        if (!tlim || tlim > 90) u.searchParams.set("limit","60");
      }
      return u.pathname + (u.search || "");
    }catch(_){
      return url;
    }
  }

  // ---- fetch guard + timeout (keep 12s) ----
  var _fetch = window.fetch;
  if (typeof _fetch === "function"){
    window.fetch = function(input, init){
      var controller = ("AbortController" in window) ? new AbortController() : null;
      init = init || {};
      if (controller && !init.signal) init.signal = controller.signal;

      var t = null;
      if (controller) t = setTimeout(function(){ try{ controller.abort(); }catch(_){} }, 12000);

      var patched = input;
      if (typeof input === "string") patched = patchUrl(input);

      return _fetch(patched, init).catch(function(e){
        window.__VSP_API_LAST_ERR__ = String(e && e.message ? e.message : e);
        throw e;
      }).finally(function(){ if (t) clearTimeout(t); });
    };
  }

  // ---- XHR guard ----
  if ("XMLHttpRequest" in window){
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url){
      try{
        if (typeof url === "string") url = patchUrl(url);
      }catch(_){}
      return _open.apply(this, [method, url].concat([].slice.call(arguments, 2)));
    };
    // set default timeout (12s)
    var _send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function(){
      try{ if (!this.timeout) this.timeout = 12000; }catch(_){}
      return _send.apply(this, arguments);
    };
  }
})();
JS

# restart service so templates serve updated JS
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
else
  echo "[WARN] no systemctl; restart manually"
fi

echo "[OK] updated $JS (fetch+XHR rid+limit)"
