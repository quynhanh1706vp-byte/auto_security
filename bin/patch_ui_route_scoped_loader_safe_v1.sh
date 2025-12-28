#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
JS_FEATURES="static/js/vsp_ui_features_v1.js"
JS_LOADER="static/js/vsp_ui_loader_route_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "$TPL.bak_route_loader_${TS}"
echo "[BACKUP] $TPL.bak_route_loader_${TS}"

mkdir -p static/js

cat > "$JS_FEATURES" <<'JS'
/* VSP_UI_FEATURES_V1 (route-scoped) */
(function(){
  'use strict';
  window.__VSP_FEATURE_FLAGS__ = window.__VSP_FEATURE_FLAGS__ || {
    DASHBOARD_CHARTS: false,
    RUNS_PANEL: false,
    DATASOURCE_TAB: false,
    SETTINGS_TAB: false,
    RULE_OVERRIDES_TAB: false
  };
})();
JS

cat > "$JS_LOADER" <<'JS'
/* VSP_UI_ROUTE_LOADER_V1: load per-route modules; never crash whole UI */
(function(){
  'use strict';
  if (window.__VSP_UI_ROUTE_LOADER_V1) return;
  window.__VSP_UI_ROUTE_LOADER_V1 = 1;

  const LOADED = new Set();
  const LOADING = new Map();

  function toast(msg){
    try{
      let el = document.getElementById('vsp-toast');
      if(!el){
        el = document.createElement('div');
        el.id = 'vsp-toast';
        el.style.cssText = [
          'position:fixed','right:16px','bottom:16px','z-index:99999',
          'max-width:520px','padding:10px 12px','border-radius:12px',
          'background:rgba(17,24,39,0.95)','color:#e5e7eb',
          'box-shadow:0 10px 30px rgba(0,0,0,0.35)',
          'font:12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Arial',
          'border:1px solid rgba(255,255,255,0.08)'
        ].join(';');
        document.body.appendChild(el);
      }
      el.textContent = msg;
      el.style.display='block';
      clearTimeout(el.__t);
      el.__t = setTimeout(()=>{ el.style.display='none'; }, 4500);
    }catch(_){}
  }

  function loadScriptOnce(src){
    if (LOADED.has(src)) return Promise.resolve(true);
    if (LOADING.has(src)) return LOADING.get(src);

    const p = new Promise((resolve) => {
      const s = document.createElement('script');
      s.src = src + (src.includes('?') ? '&' : '?') + 'v=' + Date.now();
      s.async = true;

      const done = (ok) => {
        try{ s.onload = s.onerror = null; }catch(_){}
        LOADING.delete(src);
        if(ok) LOADED.add(src);
        resolve(ok);
      };

      const t = setTimeout(() => {
        console.warn('[VSP_LOADER] timeout:', src);
        toast('JS load timeout: ' + src);
        done(false);
      }, 6000);

      s.onload = () => { clearTimeout(t); done(true); };
      s.onerror = () => {
        clearTimeout(t);
        console.warn('[VSP_LOADER] failed:', src);
        toast('JS load failed: ' + src);
        done(false);
      };

      document.head.appendChild(s);
    });

    LOADING.set(src, p);
    return p;
  }

  function normRoute(){
    let h = (location.hash || '').replace(/^#/, '').trim();
    if (!h) return 'dashboard';
    h = h.split('?')[0].split('&')[0].trim();
    // normalize synonyms
    if (h === 'runs-reports' || h === 'reports') return 'runs';
    if (h === 'data' || h === 'datasource') return 'datasource';
    if (h === 'rules' || h === 'rule-overrides') return 'rules';
    return h;
  }

  function plan(route){
    const f = (window.__VSP_FEATURE_FLAGS__ || {});
    const scripts = [];

    if (route === 'dashboard' && f.DASHBOARD_CHARTS){
      scripts.push('/static/js/vsp_dashboard_enhance_v1.js');
      scripts.push('/static/js/vsp_dashboard_charts_pretty_v3.js');
      scripts.push('/static/js/vsp_degraded_panel_hook_v3.js');
    }

    if (route === 'runs' && f.RUNS_PANEL){
      scripts.push('/static/js/vsp_runs_tab_resolved_v1.js');
    }

    if ((route === 'datasource' || route === 'data') && f.DATASOURCE_TAB){
      scripts.push('/static/js/vsp_datasource_tab_v1.js');
    }

    if (route === 'settings' && f.SETTINGS_TAB){
      scripts.push('/static/js/vsp_settings_tab_v1.js');
    }

    if ((route === 'rules') && f.RULE_OVERRIDES_TAB){
      scripts.push('/static/js/vsp_rule_overrides_tab_v1.js');
    }

    return scripts;
  }

  async function ensure(){
    const r = normRoute();
    const list = plan(r);
    if (!list.length) return;
    console.log('[VSP_LOADER] route=', r, 'scripts=', list);
    for (const src of list){
      // không “fail toàn UI” nếu 1 file hỏng
      await loadScriptOnce(src);
    }
  }

  window.addEventListener('hashchange', () => { ensure(); });

  window.addEventListener('error', (e) => {
    try{
      const msg = (e && e.message) ? e.message : 'JS error';
      console.warn('[VSP] window.error:', msg);
      toast('JS error: ' + msg);
    }catch(_){}
  });

  window.addEventListener('unhandledrejection', (e) => {
    try{
      const msg = (e && e.reason && (e.reason.message || String(e.reason))) || 'Promise rejection';
      console.warn('[VSP] unhandledrejection:', msg);
      toast('Promise rejection: ' + msg);
    }catch(_){}
  });

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', ensure);
  } else {
    ensure();
  }
})();
JS

python3 - <<PY
from pathlib import Path
p = Path("$TPL")
html = p.read_text(encoding="utf-8", errors="ignore")

# 1) comment out any direct static/js includes (để không chạy global)
import re
def repl(m):
  tag = m.group(0)
  return "<!-- VSP_DISABLED_BY_ROUTE_LOADER: " + tag.replace("--","-") + " -->"
html2 = re.sub(r'<script[^>]+src="/static/js/[^"]+"[^>]*>\s*</script>', repl, html, flags=re.I)

# 2) ensure our two safe scripts exist before </body>
ins = '\\n  <script src="/static/js/vsp_ui_features_v1.js?v=$TS"></script>\\n' + \
      '  <script src="/static/js/vsp_ui_loader_route_v1.js?v=$TS"></script>\\n'
if "</body>" in html2:
  html2 = html2.replace("</body>", ins + "</body>")
else:
  html2 = html2 + ins

p.write_text(html2, encoding="utf-8")
print("[OK] patched template with route-scoped loader")
PY

node --check "$JS_FEATURES" >/dev/null
node --check "$JS_LOADER" >/dev/null
echo "[OK] node --check OK"

echo "[NEXT] hard refresh (Ctrl+Shift+R) then test tab switching."
