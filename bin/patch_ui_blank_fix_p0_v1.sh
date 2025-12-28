#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

backup() {
  local f="$1"
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "$f.bak_blankfix_${TS}"
  echo "[BACKUP] $f.bak_blankfix_${TS}"
}

echo "== [1/2] controller: SAFE V3 =="
F="static/js/vsp_commercial_layout_controller_v1.js"
backup "$F"
cat > "$F" <<'JS'
/* VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE: route-scoped + non-destructive */
(function(){
  'use strict';
  if (window.__VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE) return;
  window.__VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE = true;

  function routeName(){
    var h = (location.hash || '').replace(/^#/, '').trim();
    if (!h) return 'dashboard';
    if (h[0] === '/') h = h.slice(1);
    return (h.split('?')[0].split('&')[0] || 'dashboard').toLowerCase();
  }
  function setDisplay(el, show){
    if (!el) return;
    el.style.display = show ? '' : 'none';
  }
  function forceNoScale(){
    try { document.documentElement.style.zoom = '1'; } catch(_) {}
    try { document.body.style.zoom = '1'; } catch(_) {}
    try { document.body.style.transform = 'none'; } catch(_) {}
    try { document.body.style.transformOrigin = '0 0'; } catch(_) {}
  }

  function policyPanel(){
    return document.getElementById('vsp-policy-verdict-panel') ||
           document.getElementById('vsp-policy-panel') ||
           document.querySelector('[data-vsp-policy-verdict-panel]');
  }

  function ensurePolicyToggle(){
    var btn = document.getElementById('vsp-policy-verdict-toggle');
    if (btn) return;
    btn = document.createElement('button');
    btn.id = 'vsp-policy-verdict-toggle';
    btn.type = 'button';
    btn.textContent = 'Policy / Verdict';
    btn.style.cssText = [
      'position:fixed','left:14px','bottom:14px','z-index:9999',
      'padding:8px 10px','border-radius:10px',
      'border:1px solid rgba(255,255,255,.12)',
      'background:rgba(17,20,28,.92)','color:#e7eaf0',
      'font-size:12px','cursor:pointer',
      'box-shadow:0 8px 22px rgba(0,0,0,.35)'
    ].join(';') + ';';
    btn.addEventListener('click', function(){
      var p = policyPanel();
      if (!p) return;
      p.style.display = (p.style.display === 'none') ? '' : 'none';
    });
    document.body.appendChild(btn);
  }

  function apply(){
    var r = routeName();
    var isRuns = (r === 'runs') || r.startsWith('runs');

    // IMPORTANT: only touch known mount points
    var runsRoot = document.getElementById('vsp-runs-main');
    setDisplay(runsRoot, isRuns);

    // default collapse policy/verdict (if exists)
    var pv = policyPanel();
    if (pv && !pv.dataset.vspCollapsedInit){
      pv.dataset.vspCollapsedInit = '1';
      pv.style.display = 'none';
    }
    ensurePolicyToggle();
    forceNoScale();

    try { console.log('[VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE] apply route=', r, 'isRuns=', isRuns); } catch(_){}
  }

  var t=null;
  function schedule(){
    if (t) clearTimeout(t);
    t = setTimeout(apply, 50);
  }
  window.addEventListener('hashchange', schedule, true);
  document.addEventListener('DOMContentLoaded', schedule, {once:true});
  setTimeout(schedule, 120);
  setTimeout(schedule, 800);
})();
JS
node --check "$F" >/dev/null && echo "[OK] controller V3 SAFE"

echo "== [2/2] tools_status: null-safe textContent/innerHTML =="
F2="static/js/vsp_tools_status_from_gate_p0_v1.js"
backup "$F2"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "__VSP_SAFE_SET_TEXT__" not in s:
  inject = r"""
  // __VSP_SAFE_SET_TEXT__: avoid null crashes when mount points are hidden by route layout
  function __VSP_SAFE_SET_TEXT__(el, v){
    if(!el) return;
    try{ el.textContent = (v==null ? "" : String(v)); }catch(_){}
  }
  function __VSP_SAFE_SET_HTML__(el, v){
    if(!el) return;
    try{ el.innerHTML = (v==null ? "" : String(v)); }catch(_){}
  }
"""
  m=re.search(r"(['\"]use strict['\"];)", s)
  s = (s[:m.end()] + inject + s[m.end():]) if m else (inject + s)

s = re.sub(r"([A-Za-z0-9_$.\[\]\(\)]+)\.textContent\s*=\s*([^;]+);",
           r"__VSP_SAFE_SET_TEXT__(\1, \2);", s)
s = re.sub(r"([A-Za-z0-9_$.\[\]\(\)]+)\.innerHTML\s*=\s*([^;]+);",
           r"__VSP_SAFE_SET_HTML__(\1, \2);", s)

p.write_text(s, encoding="utf-8")
print("[OK] tools_status made null-safe")
PY
node --check "$F2" >/dev/null && echo "[OK] tools_status null-safe"

echo "[DONE] Apply OK. Next: Ctrl+Shift+R + Ctrl+0. If still weird, restart UI then hard refresh."
