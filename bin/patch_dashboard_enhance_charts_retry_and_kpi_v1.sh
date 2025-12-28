#!/usr/bin/env bash
set -euo pipefail
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] not found: $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_dashfix_${TS}"
echo "[BACKUP] $F.bak_dashfix_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_enhance_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")

if "VSP_DASH_SAFE_TEXT_V2" not in txt:
    # Insert helpers after 'use strict'
    i = txt.find("'use strict';")
    if i != -1:
        i += len("'use strict';")
        helpers = r"""

  // === VSP_DASH_SAFE_TEXT_V2 ===
  function safeText(v){
    if (v === null || v === undefined) return '-';
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'object'){
      return String(v.id || v.cwe || v.name || v.path || v.file || v.rule || JSON.stringify(v));
    }
    return String(v);
  }
  function findChartsEngine(){
    // try known globals first
    const cand = [
      window.VSP_CHARTS_V3,
      window.VSP_CHARTS_PRETTY_V3,
      window.VSP_CHARTS_ENGINE_V3,
      window.VSP_DASH_CHARTS_V3
    ].filter(Boolean);
    for (const c of cand){
      if (c && typeof c.hydrate === 'function') return c;
    }
    // fallback: scan window keys
    try{
      for (const k of Object.keys(window)){
        if (!k || k.length > 80) continue;
        if (k.indexOf('VSP') === -1 || k.toLowerCase().indexOf('chart') === -1) continue;
        const obj = window[k];
        if (obj && typeof obj.hydrate === 'function') return obj;
      }
    }catch(e){}
    return null;
  }
  // === END VSP_DASH_SAFE_TEXT_V2 ===
"""
        txt = txt[:i] + helpers + txt[i:]

# Ensure dash data stored for retry
if "__VSP_LAST_DASH_DATA__" not in txt:
    txt = txt.replace(
        "console.log('[VSP_DASH] dashboard_v3 data =",
        "window.__VSP_LAST_DASH_DATA__ = data;\n    console.log('[VSP_DASH] dashboard_v3 data ="
    )

# Replace assignments to top-cwe/top-module if they exist
txt = re.sub(r'(getElementById\(["\']vsp-kpi-top-cwe["\']\)\.textContent\s*=\s*)([^;]+);', r'\1safeText(\2);', txt)
txt = re.sub(r'(getElementById\(["\']vsp-kpi-top-module["\']\)\.textContent\s*=\s*)([^;]+);', r'\1safeText(\2);', txt)

# Add retry block (once)
if "VSP_DASH_CHARTS_RETRY_V2" not in txt:
    txt += r"""

// === VSP_DASH_CHARTS_RETRY_V2 ===
(function(){
  try{
    let tries = 0;
    function tick(){
      tries++;
      const eng = findChartsEngine();
      if (eng && window.__VSP_LAST_DASH_DATA__){
        try{
          eng.hydrate(window.__VSP_LAST_DASH_DATA__);
          console.log('[VSP_DASH] charts hydrated via retry v2');
          return;
        }catch(e){}
      }
      if (tries < 8) setTimeout(tick, 350);
    }
    setTimeout(tick, 350);
  }catch(e){}
})();
// === END VSP_DASH_CHARTS_RETRY_V2 ===
"""

p.write_text(txt, encoding="utf-8")
print("[OK] patched dashboard enhance: safeText + findChartsEngine + retry")
PY

echo "[OK] dashboard patch done"
