#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) write P0 safe route loader v2 =="
JS="static/js/vsp_ui_loader_route_p0_v2.js"
mkdir -p static/js
cat > "$JS" <<'JS'
/* VSP_UI_LOADER_ROUTE_P0_V2: route-scoped loader that never blocks UI */
(function(){
  'use strict';
  if (window.__VSP_UI_LOADER_ROUTE_P0_V2) return;
  window.__VSP_UI_LOADER_ROUTE_P0_V2 = 1;

  const log = (...a)=>{ try{ console.log("[VSP_LOADER_P0_V2]", ...a); }catch(_){} };
  const warn = (...a)=>{ try{ console.warn("[VSP_LOADER_P0_V2]", ...a); }catch(_){} };

  const loaded = new Map(); // url -> Promise<{ok:boolean}>
  function injectScript(url){
    if (loaded.has(url)) return loaded.get(url);
    const p = new Promise((resolve)=>{
      try{
        const s = document.createElement("script");
        s.src = url;
        s.async = true;
        s.crossOrigin = "anonymous";
        let done = false;
        const finish = (ok, why)=>{
          if (done) return;
          done = true;
          if (!ok) warn("script failed/degraded:", url, why||"");
          resolve({ok: !!ok});
        };
        s.onload = ()=>finish(true);
        s.onerror = ()=>finish(false, "onerror");
        // HARD fail-safe: never hang waiting for onload
        setTimeout(()=>finish(false, "timeout"), 4000);
        (document.head || document.documentElement).appendChild(s);
      }catch(e){
        warn("inject exception:", url, e);
        resolve({ok:false});
      }
    });
    loaded.set(url, p);
    return p;
  }

  function featOn(key){
    try{
      const f = window.VSP_UI_FEATURES_V1 || window.__VSP_UI_FEATURES_V1 || null;
      if (!f) return true; // default ON if missing
      if (typeof f === "function") return !!f(key);
      if (typeof f === "object") return !!f[key];
    }catch(_){}
    return true;
  }

  const ROUTE_SCRIPTS = {
    dashboard: [
      "/static/js/vsp_dashboard_enhance_v1.js",
      "/static/js/vsp_dashboard_charts_pretty_v3.js",
      "/static/js/vsp_degraded_panel_hook_v3.js"
    ],
    runs: ["/static/js/vsp_runs_tab_resolved_v1.js"],
    datasource: ["/static/js/vsp_datasource_tab_v1.js"],
    settings: ["/static/js/vsp_settings_tab_v1.js"],
    rules: ["/static/js/vsp_rule_overrides_tab_v1.js"],
  };

  function normRoute(){
    const h = (location.hash || "").replace(/^#/, "");
    const r = (h.split("&")[0] || "").trim().toLowerCase();
    if (!r) return "dashboard";
    if (r === "artifacts") return "datasource";
    return r;
  }

  async function applyRoute(){
    const r = normRoute();
    const scripts = ROUTE_SCRIPTS[r] || [];
    log("route=", r, "scripts=", scripts);

    // feature gates (matching your toggles)
    if (r === "dashboard" && !featOn("DASHBOARD_CHARTS")) return;
    if (r === "runs" && !featOn("RUNS_PANEL")) return;
    if (r === "datasource" && !featOn("DATASOURCE_TAB")) return;
    if (r === "settings" && !featOn("SETTINGS_TAB")) return;
    if (r === "rules" && !featOn("RULE_OVERRIDES_TAB")) return;

    // load in-order but never block forever
    for (const u of scripts) {
      // add cache-buster that changes on each hard refresh anyway; keep stable per page load
      const url = u + (u.includes("?") ? "&" : "?") + "v=" + (window.__VSP_LOADER_CB || (window.__VSP_LOADER_CB = Date.now()));
      await injectScript(url);
    }

    try{
      // Some modules may expose a markStable; call if exists
      if (typeof window.__vsp_markStable === "function") window.__vsp_markStable();
    }catch(_){}
  }

  window.addEventListener("hashchange", ()=>{ applyRoute(); });
  // initial
  setTimeout(()=>applyRoute(), 0);
})();
JS
node --check "$JS" >/dev/null && echo "[OK] node --check: $JS"

echo "== (2) switch template to loader P0 v2 =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_loaderp0_${TS}" && echo "[BACKUP] $TPL.bak_loaderp0_${TS}"

python3 - <<PY
from pathlib import Path
import re
p=Path("$TPL")
s=p.read_text(encoding="utf-8", errors="ignore")

# replace any vsp_ui_loader_route_v1.js src with v2
s2=re.sub(r'/static/js/vsp_ui_loader_route_v1\.js[^"]*',
          f'/static/js/vsp_ui_loader_route_p0_v2.js?v=$TS',
          s)
if s2==s:
    print("[WARN] no vsp_ui_loader_route_v1.js tag found to replace (maybe already replaced).")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] replaced loader tag -> vsp_ui_loader_route_p0_v2.js")
PY

echo "== (3) kill drilldown TypeError at call-site (dashboard enhance) =="
JSF="$(ls -1 static/js/*dashboard*enhanc*.js 2>/dev/null | head -n1 || true)"
if [ -z "${JSF:-}" ]; then
  echo "[WARN] cannot find dashboard enhance js (skip)"
else
  cp -f "$JSF" "$JSF.bak_dd_callsite_${TS}" && echo "[BACKUP] $JSF.bak_dd_callsite_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$JSF")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_DD_CALLSAFE_P0_V2" not in s:
    stub = r'''
  // VSP_DD_CALLSAFE_P0_V2: ALWAYS call window drilldown as function, never crash
  function __VSP_DD_CALL__(/*...args*/){
    try{
      var fn = (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")
        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2
        : function(){ return {open:function(){},show:function(){},close:function(){},destroy:function(){}}; };
      return fn.apply(null, arguments);
    }catch(_){
      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};
    }
  }
'''
    # insert after first 'use strict';
    i = s.find("'use strict'")
    if i != -1:
      j = s.find(";", i)
      if j != -1:
        s = s[:j+1] + "\n" + stub + "\n" + s[j+1:]
      else:
        s = stub + s
    else:
      s = stub + s

    # replace any direct calls to VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2( with __VSP_DD_CALL__(
    s = re.sub(r'\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(', '__VSP_DD_CALL__(', s)
    p.write_text(s, encoding="utf-8")
    print("[OK] patched drilldown call-site safe in", p)
else:
    print("[OK] drilldown call-safe already present")
PY
  node --check "$JSF" >/dev/null && echo "[OK] node --check: $JSF"
fi

echo "== (4) restart 8910 (NO restore) =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "== (5) quick verify =="
curl -sS http://127.0.0.1:8910/vsp4 | grep -n "vsp_ui_loader_route_p0_v2.js" | head -n 3 || true
echo "[NEXT] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp4/#dashboard và click #runs/#datasource/#settings/#rules"
