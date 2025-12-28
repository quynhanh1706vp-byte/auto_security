#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
JS="static/js/vsp_hash_normalize_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
mkdir -p static/js

cp -f "$TPL" "$TPL.bak_hashnorm_${TS}" && echo "[BACKUP] $TPL.bak_hashnorm_${TS}"

cat > "$JS" <<'JS'
/* VSP_HASH_NORMALIZE_V1: normalize #tab=... or #route&k=v to #route */
(function(){
  'use strict';
  if (window.__VSP_HASH_NORMALIZE_V1) return;
  window.__VSP_HASH_NORMALIZE_V1 = 1;

  function parseHash(){
    let h = (location.hash || '').replace(/^#/, '').trim();
    if (!h) return { route: 'dashboard', params: {} };

    // split params by '&'
    const parts = h.split('&').filter(Boolean);
    let first = (parts[0] || '').trim();

    // support "#tab=datasource"
    if (first.startsWith('tab=')) first = first.slice(4).trim();
    else {
      // support "tab=" anywhere
      const m = h.match(/(?:^|&)tab=([^&]+)/);
      if (m && m[1]) first = String(m[1]).trim();
    }

    // normalize synonyms
    if (first === 'runs-reports' || first === 'reports') first = 'runs';
    if (first === 'data') first = 'datasource';
    if (first === 'rule-overrides') first = 'rules';

    const params = {};
    for (const p of parts.slice(1)){
      const i = p.indexOf('=');
      if (i > 0){
        const k = decodeURIComponent(p.slice(0,i));
        const v = decodeURIComponent(p.slice(i+1));
        params[k] = v;
      }
    }
    // also parse if first itself is like "datasource?x=y" (rare)
    if (first.includes('?')) first = first.split('?')[0];

    return { route: first || 'dashboard', params };
  }

  function normalize(){
    const { route, params } = parseHash();
    window.__VSP_HASH_ROUTE__ = route;
    window.__VSP_HASH_PARAMS__ = params;

    const target = '#' + route;
    if (location.hash !== target){
      try{
        history.replaceState(null, '', location.pathname + location.search + target);
        // trigger watchers
        window.dispatchEvent(new HashChangeEvent('hashchange'));
      }catch(_){}
    }
  }

  normalize();
  window.addEventListener('hashchange', normalize);
})();
JS

python3 - <<PY
from pathlib import Path
p=Path("$TPL")
html=p.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_hash_normalize_v1.js?v=' + "$TS" + '"></script>'

if "vsp_hash_normalize_v1.js" in html:
    print("[OK] normalize tag already present")
else:
    # insert as early as possible (right after <head>)
    import re
    m = re.search(r"<head[^>]*>", html, flags=re.I)
    if m:
        idx = m.end()
        html = html[:idx] + "\n  " + tag + "\n" + html[idx:]
    else:
        html = tag + "\n" + html
    p.write_text(html, encoding="utf-8")
    print("[OK] injected hash normalizer into template")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check OK: $JS"

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "[NEXT] Ctrl+Shift+R rồi mở lại URL cũ: /#datasource&sev=HIGH&limit=200 (nó sẽ tự về #datasource)."
