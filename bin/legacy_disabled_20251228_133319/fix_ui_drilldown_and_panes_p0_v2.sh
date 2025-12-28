#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) Write drilldown stub (must load BEFORE dashboard enhance) =="
DD="static/js/vsp_drilldown_stub_v1.js"
mkdir -p static/js
cp -f "$DD" "$DD.bak_${TS}" 2>/dev/null || true
cat > "$DD" <<'JS'
/* VSP_DRILLDOWN_STUB_V1: guarantee drilldown factory exists early */
(function(){
  'use strict';
  try{
    function __vsp_dd_stub(){
      try{ console.info("[VSP][DD] stub invoked"); }catch(_){}
      return { open:function(){}, show:function(){}, close:function(){}, destroy:function(){} };
    }
    if (typeof window !== "undefined") {
      if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
        window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = __vsp_dd_stub;
      }
      // some older code might reference this name too
      if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS !== "function") {
        window.VSP_DASH_DRILLDOWN_ARTIFACTS = __vsp_dd_stub;
      }
    }
  }catch(_){}
})();
JS
node --check "$DD" >/dev/null && echo "[OK] node --check: $DD"

echo "== (2) Write pane toggle V2 (hide ALL panes, show only active route) =="
PT="static/js/vsp_pane_toggle_safe_v2.js"
cp -f "$PT" "$PT.bak_${TS}" 2>/dev/null || true
cat > "$PT" <<'JS'
/* VSP_PANE_TOGGLE_SAFE_V2: show only active pane by hash route */
(function(){
  'use strict';

  function routeFromHash(){
    var h = (location.hash || '').trim();
    if (!h) return 'dashboard';
    if (h[0] === '#') h = h.slice(1);
    h = h.split('?')[0].split('&')[0];
    h = (h || 'dashboard').toLowerCase();
    if (h === '' ) h = 'dashboard';
    return h;
  }

  function collectPanes(){
    var panes = [];
    // common ids we used across patches
    var fixed = [
      'vsp-dashboard-main','vsp-runs-main','vsp-datasource-main','vsp-settings-main','vsp-rules-main',
      'vsp-dashboard-pane','vsp-runs-pane','vsp-datasource-pane','vsp-settings-pane','vsp-rules-pane'
    ];
    fixed.forEach(function(id){
      var el = document.getElementById(id);
      if (el) panes.push(el);
    });

    // generic: any container that looks like a pane
    var q = document.querySelectorAll('[id^="vsp-"][id$="-main"],[id^="vsp-"][id$="-pane"],.vsp-pane,[data-vsp-pane]');
    for (var i=0;i<q.length;i++) panes.push(q[i]);

    // unique
    var seen = new Set();
    var out = [];
    panes.forEach(function(el){
      if (!el || !el.id && !el.getAttribute) return;
      var key = el.id ? ("#"+el.id) : ("@"+(el.getAttribute('data-vsp-pane')||''));
      if (!seen.has(key)) { seen.add(key); out.push(el); }
    });
    return out;
  }

  function matchPane(route, panes){
    // try by id conventions
    var candidates = [
      'vsp-'+route+'-main',
      'vsp-'+route+'-pane'
    ];
    for (var i=0;i<candidates.length;i++){
      var el = document.getElementById(candidates[i]);
      if (el) return el;
    }
    // try by data attr
    for (var j=0;j<panes.length;j++){
      var p = panes[j];
      try{
        var dv = (p.getAttribute && (p.getAttribute('data-vsp-pane')||'')).toLowerCase();
        if (dv && dv === route) return p;
      }catch(_){}
    }
    return null;
  }

  function apply(){
    try{
      var route = routeFromHash();
      var panes = collectPanes();
      var active = matchPane(route, panes) || matchPane('dashboard', panes);

      panes.forEach(function(p){
        try{
          // hide all
          p.style.display = 'none';
          p.style.visibility = 'hidden';
        }catch(_){}
      });

      if (active){
        try{
          active.style.display = '';
          active.style.visibility = 'visible';
        }catch(_){}
      }

      try{ console.info("[VSP_PANES] route=", route, "panes=", panes.length, "active=", active && (active.id || active.getAttribute('data-vsp-pane'))); }catch(_){}
    }catch(_){}
  }

  function onReady(fn){
    if (document.readyState === 'complete' || document.readyState === 'interactive') return fn();
    document.addEventListener('DOMContentLoaded', fn);
  }

  onReady(function(){
    apply();
    window.addEventListener('hashchange', function(){ apply(); }, {passive:true});
    // sometimes router updates DOM after hashchange; apply again shortly
    setTimeout(apply, 50);
    setTimeout(apply, 250);
  });
})();
JS
node --check "$PT" >/dev/null && echo "[OK] node --check: $PT"

echo "== (3) Ensure template loads DD stub + pane toggle (once) =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_panes_dd_${TS}" && echo "[BACKUP] $TPL.bak_panes_dd_${TS}"

python3 - <<PY
from pathlib import Path
import re
tpl=Path("$TPL")
s=tpl.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_PANES_DD_INJECT_V2"
if MARK in s:
    print("[OK] template already injected")
else:
    inject = f"""
<!-- {MARK} -->
<script defer src="/static/js/vsp_drilldown_stub_v1.js?v={TS}"></script>
<script defer src="/static/js/vsp_pane_toggle_safe_v2.js?v={TS}"></script>
<!-- /{MARK} -->
"""
    if "</body>" in s:
        s = s.replace("</body>", inject + "\n</body>", 1)
    elif "</head>" in s:
        s = s.replace("</head>", "</head>\n" + inject, 1)
    else:
        s += "\n" + inject + "\n"
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected scripts into template")
PY

echo "== (4) Restart 8910 =="
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

echo "== (5) Next =="
echo "[NEXT] Ctrl+Shift+R rồi test:"
echo "  http://127.0.0.1:8910/vsp4/#dashboard"
echo "  http://127.0.0.1:8910/vsp4/#runs"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
echo "  http://127.0.0.1:8910/vsp4/#settings"
echo "  http://127.0.0.1:8910/vsp4/#rules"
echo "Mục tiêu: #runs/#datasource không còn lòi Dashboard pane, và không còn Uncaught TypeError drilldown."
