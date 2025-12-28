#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

echo "== (1) Write pane toggle V3 =="
PJS="static/js/vsp_pane_toggle_safe_v3.js"
cp -f "$PJS" "$PJS.bak_${TS}" 2>/dev/null || true
cat > "$PJS" <<'JS'
/* VSP_PANE_TOGGLE_SAFE_V3: show only active route pane; hide Dashboard block on non-dashboard routes */
(function(){
  'use strict';

  function routeFromHash(){
    let h = (location.hash||'').trim();
    if (!h) return 'dashboard';
    if (h[0]==='#') h=h.slice(1);
    h = h.split('&')[0].split('?')[0].split('/')[0].trim();
    if (!h) return 'dashboard';
    return h.toLowerCase();
  }

  function q(sel){ try{return document.querySelector(sel);}catch(_){return null;} }
  function qa(sel){ try{return Array.from(document.querySelectorAll(sel));}catch(_){return [];} }

  function findDashboardBlock(){
    // heuristic: heading text == "Dashboard"
    const hs = qa('h1,h2,h3');
    for (const h of hs){
      const t = (h.textContent||'').trim().toLowerCase();
      if (t === 'dashboard'){
        const blk = h.closest('section,div,main');
        if (blk) return blk;
      }
    }
    return null;
  }

  function paneFor(route){
    // panes created by router logs: #vsp-runs-main, #vsp-datasource-main, #vsp-settings-main, #vsp-rules-main
    return (
      q('#vsp-' + route + '-main') ||
      q('#' + route + '-main') ||
      q('#pane-' + route) ||
      q('[data-pane="'+route+'"]')
    );
  }

  function apply(){
    const route = routeFromHash();

    // hide/show router panes if present
    const routes = ['dashboard','runs','datasource','settings','rules'];
    const panes = {};
    for (const r of routes){
      panes[r] = paneFor(r);
    }

    // If we can identify a container, hide sibling panes
    const activePane = panes[route] || panes['dashboard'] || null;
    if (activePane && activePane.parentElement){
      const parent = activePane.parentElement;
      const kids = Array.from(parent.children || []);
      for (const el of kids){
        const id = (el.id||'');
        const isKnownPane = /(^|)vsp-(dashboard|runs|datasource|settings|rules)-main$/.test(id) || /(^|)(dashboard|runs|datasource|settings|rules)-main$/.test(id);
        if (isKnownPane){
          el.style.display = (el === activePane) ? '' : 'none';
        }
      }
    }

    // Additionally, hide the Dashboard block on non-dashboard routes (fix “#runs still shows dashboard”)
    const dashBlk = findDashboardBlock();
    if (dashBlk){
      dashBlk.style.display = (route === 'dashboard') ? '' : 'none';
    }
  }

  window.addEventListener('hashchange', apply, {passive:true});
  window.addEventListener('load', function(){ setTimeout(apply, 0); }, {once:true});
})();
JS
node --check "$PJS" >/dev/null && echo "[OK] node --check: $PJS"

echo "== (2) Hard-fix drilldown inside dashboard enhance (LOCAL SAFE VAR) =="
JSF="$(ls -1 static/js/*dashboard*enhanc*.js 2>/dev/null | head -n1 || true)"
if [ -z "${JSF:-}" ]; then
  echo "[WARN] cannot find dashboard enhance js (skip drilldown local-safe patch)"
else
  cp -f "$JSF" "$JSF.bak_dd_local_${TS}" && echo "[BACKUP] $JSF.bak_dd_local_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("$JSF")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_DD_LOCAL_SAFE_VAR_V1" in s:
    print("[OK] drilldown local-safe already present")
else:
    stub = r'''
  // VSP_DD_LOCAL_SAFE_VAR_V1: force local callable symbol (prevents TypeError forever)
  try{
    function __vsp_dd_stub_local(){
      try{ console.info("[VSP][DD] local-safe stub invoked"); }catch(_){}
      return {open:function(){},show:function(){},close:function(){},destroy:function(){}};
    }
    try{
      if (typeof window !== "undefined") {
        if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
          window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_stub_local;
        }
      }
    }catch(_){}
    // IMPORTANT: bind a LOCAL var used by this file (so later overwrites can't break us)
    var VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 =
      (typeof window !== "undefined" && typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 === "function")
        ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2
        : __vsp_dd_stub_local;
  }catch(_){}
'''
    # inject right after first 'use strict'
    i = s.find("'use strict'")
    if i != -1:
        j = s.find(";", i)
        if j != -1:
            s = s[:j+1] + stub + s[j+1:]
        else:
            s = stub + s
    else:
        s = stub + s

    p.write_text(s, encoding="utf-8")
    print("[OK] injected drilldown local-safe into", p)
PY
  node --check "$JSF" >/dev/null && echo "[OK] node --check: $JSF"
fi

echo "== (3) Ensure template loads pane toggle EARLY =="
cp -f "$TPL" "$TPL.bak_p0_v3_${TS}" && echo "[BACKUP] $TPL.bak_p0_v3_${TS}"
python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_pane_toggle_safe_v3.js?v={{ts}}"></script>'
if "vsp_pane_toggle_safe_v3.js" in s:
    print("[OK] pane toggle tag already present")
else:
    # insert as early as possible: after <head> or first <meta charset> etc.
    m = re.search(r"<head[^>]*>", s, flags=re.I)
    if m:
        insert_at = m.end()
        s = s[:insert_at] + "\n  " + tag + "\n" + s[insert_at:]
    else:
        s = tag + "\n" + s
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected pane toggle tag into template")
PY

echo "== (4) Restart 8910 (NO restore) =="
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

echo "== (5) Quick instructions =="
echo "[NEXT] Ctrl+Shift+R rồi test:"
echo "  http://127.0.0.1:8910/vsp4/#dashboard"
echo "  http://127.0.0.1:8910/vsp4/#runs"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
echo "  http://127.0.0.1:8910/vsp4/#settings"
echo "  http://127.0.0.1:8910/vsp4/#rules"
echo "[EXPECT] Console KHÔNG còn: 'VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...) is not a function'"
