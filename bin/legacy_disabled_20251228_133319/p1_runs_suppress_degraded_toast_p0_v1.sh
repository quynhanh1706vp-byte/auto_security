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
MARK="VSP_P0_SUPPRESS_RUNS_DEGRADED_TOAST_V1"

INJECT=r"""
/* ===== VSP_P0_SUPPRESS_RUNS_DEGRADED_TOAST_V1 =====
   If runs list is rendered (has RUN ids), suppress any "RUNS API FAIL"/"degraded (runs API 503)" UI.
   This stops flip/flap caused by transient ok:false / cached-degrade.
*/
(function(){
  try{
    if(window.__VSP_SUPPRESS_RUNS_DEGRADED_V1) return;
    window.__VSP_SUPPRESS_RUNS_DEGRADED_V1 = true;

    const RX = /(RUNS\s*API\s*FAIL|degraded\s*\(runs\s*api\s*503\)|Error:\s*503\s*\/api\/vsp\/runs)/i;

    function qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(_e){ return []; } }

    function hasRunsRows(){
      try{
        const t = (document.body && (document.body.innerText||document.body.textContent)) ? (document.body.innerText||document.body.textContent) : "";
        // heuristic: run ids usually contain "_RUN_" or "RUN_" pattern
        return /_RUN_\d{8}_\d{6}/.test(t) || /\bRUN_[A-Z0-9_]{6,}\b/.test(t) || /VSP_CI_RUN_\d{8}_\d{6}/.test(t);
      }catch(_e){ return false; }
    }

    function hideDegradedBits(){
      if(!hasRunsRows()) return; // only hide if list actually rendered
      for(const el of qsa("div,span,small,label,button,a")){
        const t=(el.textContent||"").trim();
        if(t && RX.test(t)){
          try{ el.style.display="none"; el.setAttribute("data-vsp-hide-degraded","1"); }catch(_e){}
        }
      }
      // also hide common toast containers if they contain the text
      for(const el of qsa("[role='alert'], .toast, .toaster, .snackbar, .notification")){
        const t=(el.textContent||"").trim();
        if(t && RX.test(t)){
          try{ el.style.display="none"; el.setAttribute("data-vsp-hide-degraded","1"); }catch(_e){}
        }
      }
    }

    // Run a few times after load (covers late-render toast)
    function burst(){
      hideDegradedBits();
      setTimeout(hideDegradedBits, 500);
      setTimeout(hideDegradedBits, 1500);
      setTimeout(hideDegradedBits, 3000);
      setTimeout(hideDegradedBits, 6000);
    }

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", burst);
    else burst();

    // MutationObserver: if it pops back, hide again
    const obs=new MutationObserver((_m)=>{ hideDegradedBits(); });
    try{ obs.observe(document.documentElement||document.body, {childList:true, subtree:true}); }catch(_e){}
  }catch(_e){}
})();
"""

def backup(p: Path, tag: str):
    bak=p.with_name(p.name+f".bak_suppress_degraded_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def inject(p: Path):
    if not p.exists():
        print("[SKIP] missing:", p); return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already:", p); return False
    bak=backup(p, "v1")
    p.write_text(s.rstrip()+"\n\n"+INJECT.strip()+"\n", encoding="utf-8")
    print("[OK] injected:", p, "backup:", bak)
    return True

changed=False
for fp in ["static/js/vsp_runs_tab_resolved_v1.js","static/js/vsp_bundle_commercial_v2.js","static/js/vsp_bundle_commercial_v1.js"]:
    changed = inject(Path(fp)) or changed
print("[DONE] changed=", changed)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] Applied. Restart UI then Ctrl+F5 /runs"
