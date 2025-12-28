#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fixparen_${TS}"
echo "[BACKUP] $F.bak_fixparen_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# (1) Fix the exact extra-paren: `}))();` -> `})();` near DRILL_ART_V2
fixed = 0
mark = "DRILL_ART_V2 installed"
idx = s.find(mark)

def fix_once(text: str) -> tuple[str,int]:
    if "}))();" in text:
        return text.replace("}))();", "})();", 1), 1
    return text, 0

if idx != -1:
    a = max(0, idx - 1200)
    b = min(len(s), idx + 2000)
    win = s[a:b]
    win2, n = fix_once(win)
    if n:
        s = s[:a] + win2 + s[b:]
        fixed = n
else:
    s, fixed = fix_once(s)

print("[OK] fixed_extra_paren=", fixed)

# (2) P0: make sure drilldown function exists (avoid TypeError)
BR_MARK = "VSP_DRILLDOWN_BRIDGE_P0_V2"
if BR_MARK not in s:
    s += r"""

/* VSP_DRILLDOWN_BRIDGE_P0_V2: ensure drilldown funcs exist (P0 no-crash) */
(function(){
  'use strict';
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== 'function') {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.log('[VSP][P0] drilldown artifacts (stub)'); }catch(_){}
        try{ window.location.hash = '#datasource'; }catch(_){}
      };
    }
  }catch(_e){}
})();
"""
    print("[OK] appended", BR_MARK)

# (3) P0: auto-set RID if missing -> reload once
AR_MARK = "VSP_AUTO_RID_SELECTED_P0_V1"
if AR_MARK not in s:
    s += r"""

/* VSP_AUTO_RID_SELECTED_P0_V1: if RID none -> pull latest_rid_v1, set localStorage, reload */
(function(){
  'use strict';
  if (window.__VSP_AUTO_RID_SELECTED_P0_V1) return;
  window.__VSP_AUTO_RID_SELECTED_P0_V1 = 1;

  function isBad(x){
    x = (x||'').toString().trim().toLowerCase();
    return (!x || x==='(none)' || x==='none' || x==='n/a' || x==='na');
  }

  async function ensureRid(){
    try{
      const cur = localStorage.getItem('vsp_rid_selected_v2');
      if (!isBad(cur)) return;

      const r = await fetch('/api/vsp/latest_rid_v1', { cache: 'no-store' });
      const j = await r.json().catch(()=>null);
      const rid = (j && (j.rid || j.run_id || j.runId)) ? String(j.rid || j.run_id || j.runId).trim() : '';
      if (isBad(rid)) return;

      localStorage.setItem('vsp_rid_selected_v2', rid);
      console.log('[VSP][P0] auto-set rid =>', rid);
      setTimeout(()=>{ try{ location.reload(); }catch(_){} }, 50);
    }catch(e){
      try{ console.warn('[VSP][P0] auto-set rid failed', e); }catch(_){}
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ensureRid, { once:true });
  } else {
    ensureRid();
  }
})();
"""
    print("[OK] appended", AR_MARK)

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] wrote", p.as_posix(), "bytes=", len(s))
else:
    print("[OK] no changes needed")
PY

echo "== node --check bundle v2 =="
node --check "$F"
echo "[OK] bundle v2 syntax OK"

echo "== hard reset 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== quick verify /vsp4 scripts =="
curl -sS http://127.0.0.1:8910/vsp4 \
| grep -oE 'src="[^"]+static/js/[^"]+"' \
| sed 's/src="//;s/"$//' | nl -ba
