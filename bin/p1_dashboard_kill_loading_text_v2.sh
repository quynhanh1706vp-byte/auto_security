#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_kill_loading_${TS}"
echo "[BACKUP] ${JS}.bak_kill_loading_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_KILL_LOADING_TEXT_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
/* ===== VSP_P1_DASH_KILL_LOADING_TEXT_V2 =====
   Replace stuck "Loading..." placeholders in dashboard panels after timeout.
*/
(function(){
  try{
    if (window.__VSP_DASH_KILL_LOADING_V2) return;
    window.__VSP_DASH_KILL_LOADING_V2 = true;

    function mkBadge(msg){
      try{
        var id="vsp-dash-degraded-badge-v2";
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

    function killOnce(){
      var changed=0;
      try{
        // Replace exact "Loading..." and common variants
        var nodes=document.querySelectorAll("*");
        for (var i=0;i<nodes.length;i++){
          var el=nodes[i];
          if(!el || !el.firstChild) continue;
          // only touch leaf-ish text nodes to avoid nuking big containers
          if(el.children && el.children.length>0) continue;
          var t=(el.textContent||"").trim();
          if(t==="Loading..." || t==="Loading.." || t==="Loading." || t==="Loading"){
            el.textContent="No data (degraded)";
            changed++;
          }
        }

        // Also catch dashboard list-style placeholders (many lines)
        var host=document.querySelector("#vsp-dashboard-main") || document.querySelector("main") || document.body;
        if(host){
          var txt=(host.innerText||"");
          if(txt && txt.indexOf("Loading...")>=0){
            // Best-effort: don’t rewrite whole host, just show a badge.
            mkBadge("DEGRADED: charts pending (auto-clean)");
          }
        }

      }catch(e){}
      return changed;
    }

    // Run after main fetches likely completed
    setTimeout(function(){
      try{
        var n=killOnce();
        if(n>0) mkBadge("DEGRADED: charts no data (cleaned "+n+")");
      }catch(e){}
    }, 6500);

    // One more pass later (for slow machines)
    setTimeout(function(){
      try{
        var n=killOnce();
        if(n>0) mkBadge("DEGRADED: charts no data (cleaned "+n+")");
      }catch(e){}
    }, 11000);

  }catch(e){}
})();
'''

# prepend so it runs early
s = block + "\n" + s
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[DONE] Ctrl+Shift+R: $BASE/vsp5"
echo "[CHECK] marker:"
curl -fsS "$BASE/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_P1_DASH_KILL_LOADING_TEXT_V2" | head || true
