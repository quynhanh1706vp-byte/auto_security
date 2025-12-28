#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kill_loading_v3_${TS}"
echo "[BACKUP] ${JS}.bak_kill_loading_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_KILL_LOADING_TEXT_V3"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
/* ===== VSP_P1_DASH_KILL_LOADING_TEXT_V3 =====
   Robust: replace stuck "Loading..." via TreeWalker (text nodes).
*/
(function(){
  try{
    if (window.__VSP_DASH_KILL_LOADING_V3) return;
    window.__VSP_DASH_KILL_LOADING_V3 = true;

    function badge(msg){
      try{
        var id="vsp-dash-degraded-badge-v3";
        var b=document.getElementById(id);
        if(!b){
          b=document.createElement("div");
          b.id=id;
          b.style.cssText="position:fixed;right:14px;bottom:52px;z-index:99999;padding:8px 10px;border-radius:10px;font:12px/1.2 system-ui;background:rgba(0,0,0,.75);color:#fff;border:1px solid rgba(255,255,255,.12);max-width:46vw";
          document.body.appendChild(b);
        }
        b.textContent=msg||"DEGRADED";
      }catch(e){}
    }

    function replaceLoadingOnce(){
      var changed=0;
      try{
        var root = document.querySelector("#vsp-dashboard-main") || document.body;
        if(!root) return 0;

        var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var node;
        while((node = w.nextNode())){
          var t = node.nodeValue || "";
          if(!t) continue;
          // normalize
          var tt = t.trim();
          if(tt==="Loading..." || tt==="Loading.." || tt==="Loading." || tt==="Loading"){
            node.nodeValue = t.replace(tt, "No data (degraded)");
            changed++;
            continue;
          }
          if(t.indexOf("Loading...")>=0 || t.indexOf("Loading..")>=0 || t.indexOf("Loading.")>=0){
            node.nodeValue = t.replace(/Loading\.{1,3}/g, "No data (degraded)");
            changed++;
          }
        }
      }catch(e){}
      return changed;
    }

    function run(){
      var n = replaceLoadingOnce();
      if(n>0) badge("DEGRADED: charts no data (cleaned "+n+")");
      return n;
    }

    // run after initial loads
    setTimeout(run, 1200);
    setTimeout(run, 6500);

    // catch late renders: every 2s for 16s
    var left = 8;
    var iv = setInterval(function(){
      try{
        run();
        left--;
        if(left<=0) clearInterval(iv);
      }catch(e){
        clearInterval(iv);
      }
    }, 2000);

  }catch(e){}
})();
'''

# prepend
s = block + "\n" + s
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[DONE] Ctrl+Shift+R: $BASE/vsp5"
echo "[CHECK] marker:"
curl -fsS "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_P1_DASH_KILL_LOADING_TEXT_V3" | head || true
