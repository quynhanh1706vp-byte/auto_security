#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND_JS=(
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import time

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_FORCE_NOFILTER_MUTATION_V1"

INJECT=r"""
/* ===== VSP_P0_FORCE_NOFILTER_MUTATION_V1 =====
   Keep default runs filters OFF even if:
   - checkboxes are rendered after DOMContentLoaded
   - HTML has 'checked' attribute
   Stops once user manually toggles any filter checkbox (commercial UX).
*/
(function(){
  try{
    if(window.__VSP_NOFILTER_OBS_V1) return;
    window.__VSP_NOFILTER_OBS_V1 = true;

    let userTouched=false;

    function isFilterCb(el){
      if(!el || el.type!=='checkbox') return false;
      const id=(el.id||'').toLowerCase();
      const nm=(el.name||'').toLowerCase();
      const lb=((el.getAttribute('aria-label')||'')+' '+(el.getAttribute('data-label')||'')).toLowerCase();
      const t=(id+' '+nm+' '+lb);
      return (
        t.includes('has_json') || t.includes('has_summary') || t.includes('has_sum') ||
        t.includes('has_html') || t.includes('has_csv') || t.includes('has_sarif') ||
        t.startsWith('has_') || t.includes('only_with') || t.includes('artifact')
      );
    }

    function forceOff(root){
      if(userTouched) return;
      const cbs = Array.from((root||document).querySelectorAll('input[type="checkbox"]'));
      for(const el of cbs){
        if(!isFilterCb(el)) continue;
        try{
          if(el.checked) el.checked=false;
          if(el.hasAttribute('checked')) el.removeAttribute('checked');
        }catch(e){}
      }
    }

    // Mark userTouched if they manually click any filter checkbox
    document.addEventListener('click', function(e){
      const t=e.target;
      if(t && t.matches && t.matches('input[type="checkbox"]') && isFilterCb(t)){
        userTouched=true;
        try{ window.__VSP_NOFILTER_USER_TOUCHED_V1=true; }catch(_e){}
      }
    }, true);

    // Initial enforce
    if(document.readyState==='loading'){
      document.addEventListener('DOMContentLoaded', ()=>forceOff(document));
    }else{
      forceOff(document);
    }

    // Observe future DOM additions (checkbox rendered later)
    const obs = new MutationObserver((muts)=>{
      if(userTouched) return;
      for(const m of muts){
        for(const n of Array.from(m.addedNodes||[])){
          if(n && n.querySelectorAll) forceOff(n);
        }
      }
    });
    obs.observe(document.documentElement||document.body, {childList:true, subtree:true});

    // periodic safety (very light)
    setInterval(()=>forceOff(document), 1200);
  }catch(_e){}
})();
"""

def backup(p: Path):
    b=p.with_name(p.name+f".bak_p0_v3_{TS}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[BACKUP] {b}")

def inject(p: Path):
    if not p.exists(): return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print(f"[SKIP] already has {MARK}: {p}")
        return False
    backup(p)
    p.write_text(s.rstrip()+"\n\n"+INJECT.strip()+"\n", encoding="utf-8")
    print(f"[OK] injected {MARK}: {p}")
    return True

patched=False
for fp in [
  Path("static/js/vsp_runs_tab_resolved_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
]:
  patched = inject(fp) or patched

print("[DONE] patched_any=", patched)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] P0 v3 applied. Restart UI if needed, then Ctrl+F5 /vsp5"
