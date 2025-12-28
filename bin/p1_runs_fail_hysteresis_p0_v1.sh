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
MARK="VSP_P0_RUNS_FAIL_HYSTERESIS_V1"

INJECT=r"""
/* ===== VSP_P0_RUNS_FAIL_HYSTERESIS_V1 =====
   Goal: stop RUNS API FAIL banner from flipping (transient fail vs OK)
   Logic:
     - on /api/vsp/runs json.ok==true => clear banner + lock-hide for 10s
     - on json.ok==false => increment failCount; show only if >=3
*/
(function(){
  try{
    if(window.__VSP_RUNS_FAIL_HYST_V1) return;
    window.__VSP_RUNS_FAIL_HYST_V1 = true;

    const LOCK_OK_MS = 10000;
    const FAIL_SHOW_THRESHOLD = 3;
    const FAIL_WINDOW_MS = 30000;

    const st = window.__vsp_runs_hyst_state || (window.__vsp_runs_hyst_state = {
      lastOkTs: 0,
      failCount: 0,
      firstFailTs: 0
    });

    function now(){ return Date.now(); }

    function shouldForceHide(){
      return st.lastOkTs && (now() - st.lastOkTs) < LOCK_OK_MS;
    }

    function qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(_e){ return []; } }

    function hideRunsFailUI(){
      // 1) hide by common texts
      const rx = /(RUNS\s*API\s*FAIL|degraded\s*\(runs\s*api\s*503\)|Error:\s*503\s*\/api\/vsp\/runs)/i;
      for(const el of qsa("div,span,small,label,button,a")){
        const t=(el.textContent||"").trim();
        if(t && rx.test(t)){
          try{ el.style.display="none"; el.setAttribute("data-vsp-hide","1"); }catch(_e){}
        }
      }
      // 2) hide common ids if present
      for(const id of ["runs-api-fail","vsp-runs-fail","runs_fail_banner","vsp_runs_fail_banner","vsp_ui_data_panel"]){
        const el=document.getElementById(id);
        if(el){
          const t=(el.textContent||"").toLowerCase();
          if(t.includes("runs api fail") || t.includes("error: 503") || t.includes("degraded")){
            try{ el.style.display="none"; el.setAttribute("data-vsp-hide","1"); }catch(_e){}
          }
        }
      }
    }

    function showRunsFailUI(){
      // allow showing only if threshold reached and not in ok-lock
      if(shouldForceHide()) { hideRunsFailUI(); return; }
      if(st.failCount < FAIL_SHOW_THRESHOLD) { hideRunsFailUI(); return; }

      // if UI has a banner element created elsewhere, we just stop hiding it (remove display:none)
      for(const el of qsa('[data-vsp-hide="1"]')){
        try{ el.style.display=""; el.removeAttribute("data-vsp-hide"); }catch(_e){}
      }
    }

    function onRunsJson(j){
      if(j && j.ok === true){
        st.lastOkTs = now();
        st.failCount = 0;
        st.firstFailTs = 0;
        hideRunsFailUI();
        return;
      }
      // ok=false (or missing)
      const t = now();
      if(!st.firstFailTs || (t - st.firstFailTs) > FAIL_WINDOW_MS){
        st.firstFailTs = t;
        st.failCount = 1;
      }else{
        st.failCount += 1;
      }
      showRunsFailUI();
    }

    // Wrap fetch to inspect /api/vsp/runs payload without breaking caller
    if(window.fetch && !window.__VSP_FETCH_OBS_RUNS_JSON_V1){
      window.__VSP_FETCH_OBS_RUNS_JSON_V1 = true;
      const orig = window.fetch.bind(window);
      window.fetch = async (input, init)=>{
        const r = await orig(input, init);
        try{
          let u="";
          try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_e){}
          if(u && u.includes("/api/vsp/runs")){
            // clone so we don't consume body
            const rr = r.clone();
            rr.json().then(onRunsJson).catch(()=>{ /* ignore */ });
          }
        }catch(_e){}
        return r;
      };
    }

    // MutationObserver: if ok-lock active, keep hiding any new banner nodes
    const obs = new MutationObserver((_muts)=>{
      if(shouldForceHide()) hideRunsFailUI();
    });
    try{ obs.observe(document.documentElement||document.body, {childList:true, subtree:true}); }catch(_e){}

    // initial sweep
    setTimeout(()=>{ if(shouldForceHide()) hideRunsFailUI(); }, 200);
    setTimeout(()=>{ if(shouldForceHide()) hideRunsFailUI(); }, 1200);
  }catch(_e){}
})();
"""

def backup(p: Path, tag: str):
    bak = p.with_name(p.name + f".bak_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def inject(p: Path):
    if not p.exists():
        print("[SKIP] missing:", p); return False
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already:", p); return False
    bak = backup(p, "runs_hyst")
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
