#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_commercial_layout_controller_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_move_panel_${TS}" && echo "[BACKUP] $F.bak_move_panel_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_commercial_layout_controller_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PANELIZE_POLICY_VERDICT_P0_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = r"""
  // VSP_PANELIZE_POLICY_VERDICT_P0_V1: move big Verdict/Policy blocks into a toggle panel
  function __vsp_norm_txt(t){ try{return (t||'').replace(/\s+/g,' ').trim().toLowerCase();}catch(_){return '';} }

  function __vsp_find_block_by_heading_text(label){
    label = __vsp_norm_txt(label);
    if(!label) return null;
    const hs = Array.from(document.querySelectorAll('h1,h2,h3,h4,div,strong,span'));
    for(const h of hs){
      const txt = __vsp_norm_txt(h.textContent);
      if(!txt) continue;
      // exact-ish match
      if(txt === label || txt.includes(label)){
        // choose a reasonable container to hide/move
        const box = h.closest('.vsp-card,.dashboard-card,.card,section,article,div') || h.parentElement;
        if(box && box.id !== 'vsp-runs-main') return box;
      }
    }
    return null;
  }

  function __vsp_ensure_panel(){
    let panel = document.getElementById('vsp-policy-verdict-panel');
    if(panel) return panel;

    panel = document.createElement('div');
    panel.id = 'vsp-policy-verdict-panel';
    panel.style.cssText = [
      'position:fixed','right:14px','bottom:14px','z-index:10000',
      'width:min(760px,92vw)','max-height:78vh','overflow:auto',
      'border-radius:14px','padding:12px',
      'border:1px solid rgba(255,255,255,.10)',
      'background:rgba(10,12,18,.96)','backdrop-filter: blur(6px)',
      'box-shadow:0 18px 50px rgba(0,0,0,.55)',
      'display:none'
    ].join(';') + ';';

    // header
    const head = document.createElement('div');
    head.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;';
    const title = document.createElement('div');
    title.textContent = 'Policy / Verdict';
    title.style.cssText = 'font-weight:700;font-size:13px;color:#e7eaf0;letter-spacing:.2px;';
    const close = document.createElement('button');
    close.type='button';
    close.textContent='×';
    close.style.cssText = 'width:32px;height:32px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(17,20,28,.92);color:#e7eaf0;cursor:pointer;';
    close.addEventListener('click', ()=>{ panel.style.display='none'; });
    head.appendChild(title); head.appendChild(close);
    panel.appendChild(head);

    const body = document.createElement('div');
    body.id = 'vsp-policy-verdict-panel-body';
    body.style.cssText = 'display:flex;flex-direction:column;gap:12px;';
    panel.appendChild(body);

    document.body.appendChild(panel);
    return panel;
  }

  function __vsp_ensure_panel_toggle(){
    let btn = document.getElementById('vsp-policy-verdict-toggle');
    if(btn) return btn;
    btn = document.createElement('button');
    btn.id='vsp-policy-verdict-toggle';
    btn.type='button';
    btn.textContent='Policy / Verdict';
    btn.style.cssText = [
      'position:fixed','right:14px','bottom:14px','z-index:9999',
      'padding:9px 11px','border-radius:12px',
      'border:1px solid rgba(255,255,255,.12)',
      'background:rgba(17,20,28,.92)','color:#e7eaf0',
      'font-size:12px','cursor:pointer',
      'box-shadow:0 10px 26px rgba(0,0,0,.40)'
    ].join(';') + ';';
    btn.addEventListener('click', function(){
      const panel = __vsp_ensure_panel();
      panel.style.display = (panel.style.display === 'none') ? '' : 'none';
    });
    document.body.appendChild(btn);
    return btn;
  }

  function __vsp_move_policy_verdict_into_panel(){
    const panel = __vsp_ensure_panel();
    const body = document.getElementById('vsp-policy-verdict-panel-body') || panel;

    const blocks = [];
    // find by known headings
    const b1 = __vsp_find_block_by_heading_text('OVERALL VERDICT');
    if(b1) blocks.append(b1);

    const b2 = __vsp_find_block_by_heading_text('Commercial Operational Policy');
    if(b2) blocks.append(b2);

    // also try Vietnamese labels (if any in future)
    const b3 = __vsp_find_block_by_heading_text('Chính sách vận hành');
    if(b3) blocks.append(b3);

    // de-dup
    const uniq = [];
    for(const x of blocks){
      if(!x) continue;
      if(x.id === 'vsp-policy-verdict-panel') continue;
      if(uniq.indexOf(x) >= 0) continue;
      uniq.push(x);
    }

    if(!uniq.length) return;

    __vsp_ensure_panel_toggle();

    for(const el of uniq){
      try{
        if(el.getAttribute('data-vsp-panelized') === '1') continue;
        el.setAttribute('data-vsp-panelized','1');
        // make it fit inside panel
        el.style.maxWidth = '100%';
        el.style.margin = '0';
        body.appendChild(el);
      }catch(_){}
    }

    // panel stays hidden by default
    try{ panel.style.display = 'none'; }catch(_){}
  }
"""

# inject before end of IIFE
idx = s.rfind("})();")
if idx != -1:
    s = s[:idx] + inject + "\n" + s[idx:]
else:
    s = s + "\n" + inject

# ensure apply() calls mover on every route (safe)
if "function apply()" in s and "__vsp_move_policy_verdict_into_panel" not in s:
    s = s.replace("function apply(){", "function apply(){\n    // VSP_PANELIZE_POLICY_VERDICT_P0_V1 hook\n    try{ __vsp_move_policy_verdict_into_panel(); }catch(_){}\n", 1)
else:
    # fallback: append a tiny listener at end
    s += "\ntry{ window.addEventListener('hashchange', ()=>{ try{ __vsp_move_policy_verdict_into_panel(); }catch(_){} }); }catch(_){ }\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched controller: panelize policy/verdict")
PY

node --check "$F" >/dev/null && echo "[OK] node --check controller" || { echo "[ERR] controller syntax failed"; exit 3; }

echo "[DONE] Restart UI + Ctrl+Shift+R + Ctrl+0"
