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
    } catch(_){}
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
    try{ apply(); } catch(_){}
  });

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', apply);
  }else{
    apply();
  }
})();
