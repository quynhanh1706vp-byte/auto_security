#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_ui_hide_runs_strip_on_other_tabs_p1_v1.js"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_hiderunsstrip_${TS}" && echo "[BACKUP] $TPL.bak_hiderunsstrip_${TS}"
[ -f "$JSF" ] && cp -f "$JSF" "$JSF.bak_${TS}" && echo "[BACKUP] $JSF.bak_${TS}"

cat > "$JSF" <<'JS'
(function(){
  'use strict';
  if (window.__VSP_HIDE_RUNS_STRIP_P1_V1) return;
  window.__VSP_HIDE_RUNS_STRIP_P1_V1 = true;

  const TAG='VSP_HIDE_RUNS_STRIP_P1_V1';

  function findRunsStrip(){
    // Heuristic: find the bar that contains "Limit" + "Has findings" + "Degraded" near the top
    const els=[...document.querySelectorAll('div,section,header')];
    for (const el of els){
      const tx=(el.innerText||'');
      if (tx.includes('Limit') && tx.includes('Has findings') && tx.includes('Degraded') && tx.includes('Search')){
        return el;
      }
    }
    return null;
  }

  function setVisible(isRuns){
    const strip=findRunsStrip();
    if (!strip) return;
    // hide the whole parent block (usually card/container)
    const box = strip.closest('.vsp-card, .dashboard-card, section, div') || strip;
    box.style.display = isRuns ? '' : 'none';
  }

  function onRoute(){
    const h=(location.hash||'').toLowerCase();
    const isRuns = (h==='#runs' || h.startsWith('#runs'));
    setVisible(isRuns);
    console.log(`[${TAG}] route=${h} isRuns=${isRuns}`);
  }

  window.addEventListener('hashchange', onRoute);
  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', onRoute, {once:true});
  else onRoute();
})();
JS

python3 - <<'PY'
from pathlib import Path
import re, datetime
tpl=Path("templates/vsp_dashboard_2025.html")
t=tpl.read_text(encoding="utf-8", errors="ignore")
if "vsp_ui_hide_runs_strip_on_other_tabs_p1_v1.js" not in t:
  stamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
  tag=f'<script src="/static/js/vsp_ui_hide_runs_strip_on_other_tabs_p1_v1.js?v={stamp}" defer></script>'
  t=re.sub(r"</body>", tag+"\n</body>", t, count=1, flags=re.I)
tpl.write_text(t, encoding="utf-8")
print("[OK] injected hide-runs-strip script")
PY

node --check "$JSF" >/dev/null && echo "[OK] node --check"
echo "[OK] patched hide-runs-strip"
echo "[NEXT] restart UI + hard refresh"
