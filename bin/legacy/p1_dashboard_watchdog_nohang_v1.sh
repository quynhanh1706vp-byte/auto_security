#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_watchdog_${TS}"
echo "[BACKUP] ${JS}.bak_dash_watchdog_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_WATCHDOG_NOHANG_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

wd = r'''
/* ===== VSP_P1_DASH_WATCHDOG_NOHANG_V1 =====
   If dashboard stays in "loading" too long, force exit loading + show degraded note.
*/
(function(){
  try{
    if (window.__VSP_DASH_WD_V1) return;
    window.__VSP_DASH_WD_V1 = true;

    function q(sel){ try{return document.querySelector(sel);}catch(e){return null;} }
    function text(el, t){ try{ if(el) el.textContent = String(t||""); }catch(e){} }

    function markDegraded(msg){
      // Try common places first; fallback: small toast in corner
      const host = q("#vsp-dashboard-main") || q("main") || document.body;
      if(!host) return;
      let b = q("#vsp-dash-degraded-badge-v1");
      if(!b){
        b = document.createElement("div");
        b.id = "vsp-dash-degraded-badge-v1";
        b.style.cssText = "position:fixed;right:14px;bottom:14px;z-index:99999;padding:8px 10px;border-radius:10px;font:12px/1.2 system-ui;background:rgba(0,0,0,.75);color:#fff;border:1px solid rgba(255,255,255,.12);max-width:46vw";
        document.body.appendChild(b);
      }
      text(b, msg || "DEGRADED");
    }

    function stopLoading(){
      // Common loaders/spinners
      const loaders = [
        "#vsp-loading", "#vsp-loader", ".vsp-loader", ".loading", ".spinner",
        "#vsp-dashboard-loading", "#vsp-dashboard-skeleton", ".vsp-skeleton"
      ];
      loaders.forEach(sel=>{
        const el = q(sel);
        if(el) try{ el.style.display="none"; }catch(e){}
      });
      // Also remove "is-loading" body class if any
      try{ document.body.classList.remove("loading","is-loading","vsp-loading"); }catch(e){}
    }

    // After 6 seconds, if still looks loading, force stop.
    setTimeout(function(){
      try{
        // Heuristic: if any loader element still visible OR key KPI nodes empty
        const loader = q("#vsp-dashboard-loading") || q(".vsp-skeleton") || q("#vsp-loading") || q(".spinner");
        const kpi = q("[data-kpi]") || q(".kpi") || q(".vsp-kpi");
        const looksLoading = !!loader && (loader.offsetParent !== null);
        const looksEmpty = !kpi;
        if(looksLoading || looksEmpty){
          stopLoading();
          markDegraded("DEGRADED: dashboard data not ready (watchdog)");
        }
      }catch(e){}
    }, 6000);

  }catch(e){}
})();
'''

# prepend watchdog at very top (so it runs early)
s = wd + "\n" + s
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[DONE] Hard refresh: ${VSP_UI_BASE:-http://127.0.0.1:8910}/vsp5 (Ctrl+Shift+R)"
echo "[CHECK] marker:"
curl -fsS "${VSP_UI_BASE:-http://127.0.0.1:8910}/static/js/vsp_bundle_tabs5_v1.js" | grep -n "VSP_P1_DASH_WATCHDOG_NOHANG_V1" | head || true
