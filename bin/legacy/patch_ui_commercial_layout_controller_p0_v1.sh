#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
CSS="static/css/vsp_commercial_layout_controller_p0_v1.css"
JS="static/js/vsp_commercial_layout_controller_p0_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_commercial_layout_${TS}"
echo "[BACKUP] $TPL.bak_commercial_layout_${TS}"

mkdir -p "$(dirname "$CSS")" "$(dirname "$JS")"

cat > "$CSS" <<'CSS'
/* VSP_COMMERCIAL_LAYOUT_CONTROLLER_P0_V1 */
:root{
  --vsp-maxw: 1400px;
  --vsp-pad: 24px;
}

html, body{
  height: 100%;
}

/* hard override accidental page scaling */
body{ zoom: 1 !important; }
#root, #app, #main, main, .main, .content, #content{
  transform: none !important;
}

body.vsp-commercial-2025{
  margin: 0;
}

/* main container widen + readable */
.vsp-commercial-2025 .vsp-commercial-container{
  max-width: var(--vsp-maxw);
  margin: 0 auto;
  padding: var(--vsp-pad);
}

/* keep top strip neat when visible */
.vsp-commercial-2025 .vsp-runs-strip{
  position: sticky;
  top: 0;
  z-index: 50;
  backdrop-filter: blur(10px);
}

/* hide blocks when controller says so */
.vsp-commercial-2025 .vsp-hidden{ display:none !important; }

/* floating action button for Policy/Verdict */
.vsp-commercial-2025 .vsp-fab{
  position: fixed;
  right: 16px;
  bottom: 16px;
  z-index: 9999;
  border: 1px solid rgba(255,255,255,.18);
  border-radius: 999px;
  padding: 10px 14px;
  font-size: 12px;
  cursor: pointer;
  background: rgba(20,24,40,.72);
  color: rgba(255,255,255,.92);
  box-shadow: 0 10px 30px rgba(0,0,0,.35);
}

.vsp-commercial-2025 .vsp-fab:hover{
  filter: brightness(1.08);
}

/* compact tables a bit */
.vsp-commercial-2025 table{
  font-size: 12.5px;
}
CSS

cat > "$JS" <<'JS'
/* VSP_COMMERCIAL_LAYOUT_CONTROLLER_P0_V1 */
(function(){
  'use strict';
  if (window.__VSP_COMMERCIAL_LAYOUT_CONTROLLER_P0_V1) return;
  window.__VSP_COMMERCIAL_LAYOUT_CONTROLLER_P0_V1 = true;

  function routeFromHash(){
    const h = (location.hash || '').replace(/^#/, '').trim().toLowerCase();
    if (!h) return 'dashboard';
    if (h.startsWith('run')) return 'runs';
    if (h.startsWith('data')) return 'datasource';
    if (h.startsWith('set')) return 'settings';
    if (h.startsWith('rule')) return 'rules';
    if (h.startsWith('dash')) return 'dashboard';
    return h;
  }

  function findByText(re){
    const nodes = document.querySelectorAll('h1,h2,h3,h4,header,section,div');
    for (const el of nodes){
      const t = (el.textContent || '').trim();
      if (!t) continue;
      if (re.test(t)) return el;
    }
    return null;
  }

  function markContainer(el, className){
    if (!el) return null;
    let cur = el;
    for (let i=0; i<10 && cur && cur !== document.body; i++){
      const r = cur.getBoundingClientRect();
      if (r.width > 700 && r.height > 80){
        cur.classList.add(className);
        return cur;
      }
      cur = cur.parentElement;
    }
    (el.parentElement || el).classList.add(className);
    return (el.parentElement || el);
  }

  function ensureCommercialContainer(){
    // pick the “main app” area by locating brand header text
    const brand = findByText(/VersaSecure Platform/i) || findByText(/SECURITY_BUNDLE/i);
    if (!brand) return null;
    const box = markContainer(brand, 'vsp-commercial-container');
    return box;
  }

  function detectRunsStrip(){
    // top strip usually contains "Degraded tools"
    const degraded = findByText(/Degraded tools/i);
    if (!degraded) return null;
    return markContainer(degraded, 'vsp-runs-strip');
  }

  function detectPolicyBlock(){
    // bottom block contains "Commercial Operational Policy" or "OVERALL VERDICT"
    const pol = findByText(/Commercial Operational Policy/i) || findByText(/OVERALL VERDICT/i);
    if (!pol) return null;
    return markContainer(pol, 'vsp-policy-block');
  }

  function hardUnscaleIfNeeded(container){
    if (!container) return;
    try{
      const cs = getComputedStyle(container);
      if (cs.transform && cs.transform !== 'none'){
        container.style.transform = 'none';
      }
    }catch(_){}
  }

  function setVisibility(route, runsStrip, policyBlock){
    // show runs strip ONLY on runs tab
    if (runsStrip){
      if (route === 'runs') runsStrip.classList.remove('vsp-hidden');
      else runsStrip.classList.add('vsp-hidden');
    }

    // policy block: hide by default, open via FAB (still accessible)
    if (policyBlock){
      policyBlock.classList.add('vsp-hidden');
      policyBlock.dataset.vspPolicyHidden = '1';
    }
  }

  function ensurePolicyFab(policyBlock){
    if (!policyBlock) return;
    if (document.querySelector('.vsp-fab[data-kind="policy"]')) return;

    const btn = document.createElement('button');
    btn.className = 'vsp-fab';
    btn.dataset.kind = 'policy';
    btn.textContent = 'Policy / Verdict';
    btn.addEventListener('click', function(){
      const hidden = policyBlock.classList.contains('vsp-hidden');
      if (hidden){
        policyBlock.classList.remove('vsp-hidden');
        policyBlock.scrollIntoView({behavior:'smooth', block:'start'});
      }else{
        policyBlock.classList.add('vsp-hidden');
      }
    });
    document.body.appendChild(btn);
  }

  function apply(){
    document.body.classList.add('vsp-commercial-2025');

    const route = routeFromHash();
    document.documentElement.dataset.vspRoute = route;

    const container = ensureCommercialContainer();
    hardUnscaleIfNeeded(container);

    const runsStrip = detectRunsStrip();
    const policyBlock = detectPolicyBlock();

    setVisibility(route, runsStrip, policyBlock);
    ensurePolicyFab(policyBlock);
  }

  window.addEventListener('hashchange', function(){
    try{ apply(); }catch(_){}
  });

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', apply);
  }else{
    apply();
  }
})();
JS

python3 - <<PY
from pathlib import Path
import re

tpl = Path("$TPL")
t = tpl.read_text(encoding="utf-8", errors="ignore")

link = '<link rel="stylesheet" href="/static/css/vsp_commercial_layout_controller_p0_v1.css?v=1">'
script = '<script defer src="/static/js/vsp_commercial_layout_controller_p0_v1.js?v=1"></script>'

if link not in t:
    t2 = re.sub(r'(</head>)', link + "\n\\1", t, flags=re.I)
    if t2 == t:
        raise SystemExit("[ERR] cannot inject CSS link (missing </head>?)")
    t = t2

if script not in t:
    t2 = re.sub(r'(</body>)', script + "\n\\1", t, flags=re.I)
    if t2 == t:
        raise SystemExit("[ERR] cannot inject JS script (missing </body>?)")
    t = t2

tpl.write_text(t, encoding="utf-8")
print("[OK] injected commercial layout controller into template")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check"
echo "[NEXT] restart UI + hard refresh (Ctrl+Shift+R) + reset browser zoom (Ctrl+0)"
