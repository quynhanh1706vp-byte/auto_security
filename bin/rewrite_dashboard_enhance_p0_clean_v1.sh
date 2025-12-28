#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

F_OLD="static/js/vsp_dashboard_enhance_v1.js"
F_NEW="static/js/vsp_dashboard_enhance_p0_clean_v1.js"
TPL="templates/vsp_dashboard_2025.html"

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "$f.bak_rewrite_${TS}"
  echo "[BACKUP] $f.bak_rewrite_${TS}"
}

backup "$F_OLD"
backup "$TPL"

cat > "$F_NEW" <<'JS'
/* VSP_DASHBOARD_ENHANCE_P0_CLEAN_V1
 * P0 goal: NO red console errors, no drilldown symbol usage, safe degrade.
 */
(function(){
  'use strict';

  const TAG = '[VSP_DASH_P0_CLEAN]';

  function $(sel, root){ try{ return (root||document).querySelector(sel); }catch(_){ return null; } }
  function $all(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(_){ return []; } }

  async function fetchJSON(url, opts){
    try{
      const r = await fetch(url, Object.assign({cache:'no-store'}, opts||{}));
      if(!r.ok) throw new Error('HTTP '+r.status);
      return await r.json();
    }catch(e){
      console.warn(TAG, 'fetch failed', url, e);
      return null;
    }
  }

  function setText(id, txt){
    const el = document.getElementById(id);
    if(!el) return;
    el.textContent = (txt==null?'':String(txt));
  }

  function safeInit(){
    // Do NOT reference VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 at all.
    // Only do harmless hydration.
    console.log(TAG, 'loaded');

    // 1) Try read dashboard data (best effort)
    fetchJSON('/api/vsp/dashboard_v3').then(d=>{
      if(!d){ return; }
      try{
        // If your template has any of these ids, fill them. If not, no-op.
        if (d.by_severity && typeof d.by_severity === 'object'){
          setText('kpi-total', d.by_severity.TOTAL ?? d.total ?? '');
          setText('kpi-critical', d.by_severity.CRITICAL ?? '');
          setText('kpi-high', d.by_severity.HIGH ?? '');
          setText('kpi-medium', d.by_severity.MEDIUM ?? '');
          setText('kpi-low', d.by_severity.LOW ?? '');
          setText('kpi-info', d.by_severity.INFO ?? '');
          setText('kpi-trace', d.by_severity.TRACE ?? '');
        }
      }catch(e){
        console.warn(TAG, 'render kpi failed', e);
      }
    });

    // 2) Gate: keep whatever other modules do; we just avoid crashing.
    // If you want, we can add canonical gate wiring later.

    // 3) Charts: do nothing here. Avoid bootstrap retry spam.
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', safeInit, {once:true});
  }else{
    safeInit();
  }
})();
JS

echo "[OK] wrote $F_NEW"
node --check "$F_NEW" >/dev/null && echo "[OK] node --check $F_NEW"

# Patch template: replace any vsp_dashboard_enhance_v1.js include with the new clean file
python3 - <<PY
from pathlib import Path
import re
tpl = Path("$TPL")
s = tpl.read_text(encoding="utf-8", errors="ignore")

# Replace old enhance include (with or without query string)
s2, n = re.subn(r'/static/js/vsp_dashboard_enhance_v1\.js(\?[^"]*)?', '/static/js/vsp_dashboard_enhance_p0_clean_v1.js?v=$TS', s)

# If not found, append script near end of body (safe)
if n == 0:
  ins = f'\\n<script src="/static/js/vsp_dashboard_enhance_p0_clean_v1.js?v=$TS"></script>\\n'
  if '</body>' in s2:
    s2 = s2.replace('</body>', ins + '</body>')
  else:
    s2 += ins
  print("[WARN] old enhance include not found; appended new script")
else:
  print("[OK] replaced enhance include count=", n)

tpl.write_text(s2, encoding="utf-8")
print("[OK] patched template", tpl)
PY

echo "== VERIFY template points to new JS =="
grep -n "vsp_dashboard_enhance_p0_clean_v1.js" "$TPL" || true

echo "[DONE] rewrite dashboard enhance P0 clean v1"
