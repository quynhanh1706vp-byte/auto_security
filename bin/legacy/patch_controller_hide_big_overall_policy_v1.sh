#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_commercial_layout_controller_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_bigverdict_${TS}" && echo "[BACKUP] $F.bak_bigverdict_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_commercial_layout_controller_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# Replace hideOriginVerdictPolicy() with a "big-panel" detector
pattern = r"function\s+hideOriginVerdictPolicy\s*\(\)\s*\{.*?\n\s*\}\n"
new_fn = r"""
  function __vsp_pick_big_panel(label, mustWords){
    const want = norm(label);
    const req = (mustWords||[]).map(norm).filter(Boolean);
    let best = null;
    let bestArea = 0;

    // search likely containers only (avoid scanning every node)
    const cand = qsa('section,article,div');
    for(const el of cand){
      try{
        if(!el) continue;
        if(el.id === 'vspPolicyPanelV4') continue;
        if(el.closest && el.closest('#vspPolicyPanelV4')) continue;

        const t = norm(el.textContent);
        if(!t) continue;
        if(!t.includes(want)) continue;

        // must contain these words to target the BIG panel, not the small card
        let ok = true;
        for(const w of req){
          if(!w) continue;
          if(!t.includes(w)){ ok=false; break; }
        }
        if(!ok) continue;

        const r = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
        if(!r) continue;
        const area = Math.max(0, r.width) * Math.max(0, r.height);

        // ignore tiny cards
        if(area < 60000) continue;

        if(area > bestArea){
          bestArea = area;
          best = el;
        }
      }catch(_){}
    }
    return best;
  }

  function hideOriginVerdictPolicy(){
    // BIG "OVERALL VERDICT" panel usually contains Updated/RID/Source/Reasons
    const bigVerdict = __vsp_pick_big_panel('OVERALL VERDICT', ['updated', 'rid', 'source', 'reasons']);

    // BIG policy panel usually contains "8 tools" and "timeout/degraded"
    const bigPolicy = __vsp_pick_big_panel('Commercial Operational Policy', ['8 tools']);

    [bigVerdict, bigPolicy].forEach(b=>{
      if(!b) return;
      try{
        if(b.getAttribute('data-vsp-origin-hidden') === '1') return;
        b.setAttribute('data-vsp-origin-hidden','1');
        b.style.display = 'none';
      }catch(_){}
    });
  }
"""

if not re.search(pattern, s, flags=re.S):
    raise SystemExit("[ERR] cannot find hideOriginVerdictPolicy() to patch")

s2 = re.sub(pattern, new_fn + "\n", s, flags=re.S, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] patched hideOriginVerdictPolicy() with big-panel matcher")
PY

node --check "$F" >/dev/null && echo "[OK] node --check controller" || { echo "[ERR] controller syntax failed"; exit 3; }

echo "[DONE] Restart UI then Ctrl+0 + Ctrl+Shift+R"
