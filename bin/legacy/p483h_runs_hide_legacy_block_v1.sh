#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483h_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p483h_${TS}"
echo "[OK] backup => ${F}.bak_p483h_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P483H_HIDE_LEGACY_RUNS_V1"
if MARK in s:
    print("[OK] already patched P483h")
else:
    add=r"""
/* VSP_P483H_HIDE_LEGACY_RUNS_V1
 * Hide legacy Runs blocks that still appear below the new commercial list.
 * Safe: only hides blocks containing legacy text markers, never touches our root.
 */
(function(){
  'use strict';
  const ROOT_ID='vsp_runs_commercial_root_v1';
  const tag='[P483h]';

  function log(){ try{ console.log(tag, ...arguments);}catch(e){} }

  function shouldHideCardText(t){
    if (!t) return false;
    // Legacy markers seen in your screenshots:
    if (t.includes('Pick a RID') && t.includes('open Dashboard')) return true;
    if (t.includes('Filter by RID') && t.includes('LABEL/TS') && t.includes('ACTIONS')) return true;
    if (t.includes('No runs found (yet)') && t.includes('run history')) return true;
    return false;
  }

  function hideOnce(){
    const root=document.getElementById(ROOT_ID);
    if(!root) return;

    const candidates=document.querySelectorAll('.vsp_card, .card, .panel, section, article, div');
    let hidden=0;
    candidates.forEach(el=>{
      if(!el) return;
      if(root.contains(el)) return;
      if(el.id===ROOT_ID) return;
      if(el.dataset && el.dataset.vspKeep==='1') return;

      const t=(el.innerText||'').trim();
      if(!t) return;

      if(shouldHideCardText(t)){
        el.style.display='none';
        hidden++;
      }
    });
    if(hidden) log('legacy blocks hidden:', hidden);
  }

  // Run a few times because legacy scripts may render late
  let n=0;
  const timer=setInterval(()=>{
    try{ hideOnce(); }catch(e){}
    n++;
    if(n>=14) clearInterval(timer);
  }, 250);

  // Also run on DOMContentLoaded if needed
  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', ()=>{ try{ hideOnce(); }catch(e){} }, {once:true});
  } else {
    try{ hideOnce(); }catch(e){}
  }
})();
"""
    p.write_text(s + "\n\n" + add, encoding="utf-8")
    print("[OK] appended P483h")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" | tee -a "$OUT/log.txt"
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P483h done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
