#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kill_loading_v4_${TS}"
echo "[BACKUP] ${JS}.bak_kill_loading_v4_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_KILL_LOADING_TEXT_V4"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
/* ===== VSP_P1_DASH_KILL_LOADING_TEXT_V4 =====
   MutationObserver + TreeWalker over document.body to eliminate stuck "Loading..."
   Expose: window.__vspDashKillLoadingNow()
*/
(function(){
  try{
    if (window.__VSP_DASH_KILL_LOADING_V4) return;
    window.__VSP_DASH_KILL_LOADING_V4 = true;

    function safeBadge(msg){
      try{
        var id="vsp-dash-degraded-badge-v4";
        var b=document.getElementById(id);
        if(!b){
          b=document.createElement("div");
          b.id=id;
          b.style.cssText=[
            "position:fixed","right:14px","bottom:52px","z-index:99999",
            "padding:8px 10px","border-radius:10px",
            "font:12px/1.2 system-ui",
            "background:rgba(0,0,0,.78)","color:#fff",
            "border:1px solid rgba(255,255,255,.14)",
            "max-width:46vw","pointer-events:none"
          ].join(";");
          (document.body||document.documentElement).appendChild(b);
        }
        b.textContent = msg || "DEGRADED";
      }catch(e){}
    }

    function normalizeLoading(t){
      // handle ASCII and unicode ellipsis
      // examples: "Loading...", "Loading..", "Loading.", "Loading", "Loading…"
      var tt = (t||"").trim();
      if (!tt) return null;
      if (tt==="Loading" || tt==="Loading." || tt==="Loading.." || tt==="Loading..." || tt==="Loading…") return tt;
      if (tt.indexOf("Loading")>=0) return tt;
      return null;
    }

    function replaceLoadingOnce(){
      var changed=0;
      try{
        var root = document.body || document.documentElement;
        if(!root) return 0;

        var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var node;
        while((node = w.nextNode())){
          var t = node.nodeValue || "";
          if(!t) continue;

          // skip script/style text nodes (paranoid)
          var pn = node.parentNode && node.parentNode.nodeName ? String(node.parentNode.nodeName).toLowerCase() : "";
          if (pn==="script" || pn==="style" || pn==="textarea") continue;

          var hit = normalizeLoading(t);
          if(!hit) continue;

          // Replace only the "Loading..." parts, keep other text around it
          var out = t
            .replace(/Loading\.{0,3}/g, "No data (degraded)")
            .replace(/Loading…/g, "No data (degraded)");

          if (out !== t){
            node.nodeValue = out;
            changed++;
          }
        }
      }catch(e){}
      return changed;
    }

    var pending=false;
    function runDebounced(){
      if(pending) return;
      pending=true;
      setTimeout(function(){
        pending=false;
        var n = replaceLoadingOnce();
        if(n>0) safeBadge("DEGRADED: charts no data (cleaned "+n+")");
      }, 80);
    }

    function start(){
      // initial passes
      runDebounced();
      setTimeout(runDebounced, 1200);
      setTimeout(runDebounced, 4500);
      setTimeout(runDebounced, 9000);

      // observe DOM changes and clean again
      try{
        var obs = new MutationObserver(function(){ runDebounced(); });
        obs.observe(document.body || document.documentElement, {subtree:true, childList:true, characterData:true});
      }catch(e){}
    }

    // expose manual trigger
    window.__vspDashKillLoadingNow = function(){
      try{
        var n = replaceLoadingOnce();
        safeBadge("DEGRADED: manual cleaned "+n);
        return n;
      }catch(e){ return -1; }
    };

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", start, {once:true});
    } else {
      start();
    }
  }catch(e){}
})();
'''
# prepend
p.write_text(block + "\n" + s, encoding="utf-8")
print("[OK] patched", p)
PY

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[DONE] Ctrl+Shift+R: $BASE/vsp5"
echo "[CHECK] marker:"
curl -fsS "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_P1_DASH_KILL_LOADING_TEXT_V4" | head || true
