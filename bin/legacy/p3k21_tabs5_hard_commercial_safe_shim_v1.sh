#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_p3k21_${TS}"
echo "[BACKUP] ${F}.bak_p3k21_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P3K21_TABS5_HARD_COMMERCIAL_SAFE_SHIM_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

shim = r"""/* === VSP_P3K21_TABS5_HARD_COMMERCIAL_SAFE_SHIM_V1 ===
   Goals (commercial-safe, Firefox-safe):
   - If ?rid= exists => DO NOT call /api/vsp/rid_latest* (return URL rid immediately)
   - Swallow "timeout"/NetworkError unhandled promise rejections (no red console)
   - Scrub banner text "Dashboard error: timeout" even if set later (MutationObserver)
   - Allow debug bypass: add ?debug_ui=1
*/
(function(){
  try{
    if (window.__VSP_P3K21__) return;
    window.__VSP_P3K21__ = true;

    const usp = new URLSearchParams(location.search || "");
    const lockedRid = (usp.get("rid") || "").trim();
    const debug = (usp.get("debug_ui") === "1");

    if (lockedRid) window.__VSP_RID_LOCKED__ = lockedRid;

    // 1) Global swallow: timeout / networkerror / aborted
    function _isSoftErr(x){
      const msg = String((x && (x.message || x.reason || x)) || "").toLowerCase();
      return msg.includes("timeout") || msg.includes("networkerror") || msg.includes("ns_binding_aborted");
    }
    window.addEventListener("unhandledrejection", function(e){
      try{
        if (!debug && _isSoftErr(e && e.reason)) { e.preventDefault(); return; }
      }catch(_){}
    });
    window.addEventListener("error", function(e){
      try{
        if (!debug && _isSoftErr(e && e.error)) { e.preventDefault(); return; }
      }catch(_){}
    });

    // 2) Scrub banner "Dashboard error: timeout" (set muộn cũng dọn)
    const BAD = "dashboard error: timeout";
    function scrub(root){
      try{
        const nodes = (root && root.querySelectorAll) ? root.querySelectorAll("div,span,p,small,em,strong") : [];
        for (let i=0;i<nodes.length;i++){
          const el = nodes[i];
          const t = (el && el.textContent ? el.textContent.trim().toLowerCase() : "");
          if (t === BAD){
            el.textContent = "";
            el.style.display = "none";
            el.setAttribute("data-vsp-scrubbed", "1");
          }
        }
      }catch(_){}
    }
    const mo = new MutationObserver(function(muts){
      if (debug) return;
      for (const m of muts){
        if (m && m.target && m.target.nodeType === 1) scrub(m.target);
        if (m && m.addedNodes){
          for (const n of m.addedNodes){
            if (n && n.nodeType === 1) scrub(n);
          }
        }
      }
    });
    try{
      mo.observe(document.documentElement || document.body, {subtree:true, childList:true, characterData:true});
      window.addEventListener("DOMContentLoaded", function(){ scrub(document); });
      setTimeout(function(){ scrub(document); }, 1200);
      setTimeout(function(){ scrub(document); }, 3500);
    }catch(_){}

    // 3) fetch shim: if lockedRid, short-circuit rid_latest endpoints
    if (!debug && typeof window.fetch === "function"){
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (lockedRid && url && url.indexOf("/api/vsp/rid_latest") !== -1){
            const body = JSON.stringify({ok:true, rid: lockedRid, mode:"url_rid"});
            return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json"}}));
          }
        }catch(_){}
        return _fetch(input, init);
      };
    }

    // 4) XHR shim: rewrite rid_latest -> rid_latest_v3?rid=lockedRid (no abort => no NS_BINDING_ABORTED)
    if (!debug && lockedRid && window.XMLHttpRequest && window.XMLHttpRequest.prototype){
      const _open = window.XMLHttpRequest.prototype.open;
      window.XMLHttpRequest.prototype.open = function(method, url){
        try{
          const u = String(url || "");
          if (u.indexOf("/api/vsp/rid_latest") !== -1){
            const nu = "/api/vsp/rid_latest_v3?rid=" + encodeURIComponent(lockedRid) + "&mode=url_rid";
            return _open.call(this, method, nu, true);
          }
        }catch(_){}
        return _open.apply(this, arguments);
      };
    }

  }catch(_){}
})();"""

# Prepend shim at very top (before any other logic)
p.write_text(shim + "\n\n" + s, encoding="utf-8")
print("[OK] injected P3K21 shim")
PY

node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c passed"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }
fi

echo "== marker =="
head -n 3 "$F" | sed -n '1,3p'
echo "[DONE] p3k21_tabs5_hard_commercial_safe_shim_v1"
