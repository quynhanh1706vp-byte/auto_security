#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND_JS=(
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")

# --------- (A) Patch DASH V6D: remove "give up" abort/return patterns ----------
MARK_A="VSP_P0_DASH_V6D_NO_GIVEUP_V1"

def backup(p: Path, tag: str):
    bak=p.with_name(p.name+f".bak_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def patch_dash_v6d(p: Path):
    if not p.exists(): 
        print("[SKIP] missing:", p); 
        return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK_A in s:
        print("[SKIP] already:", p)
        return False

    orig=s
    n=0

    # Pattern 1: if(!ok){ console.warn("...containers/rid missing"); return; }
    s, k = re.subn(
        r'if\s*\(\s*!ok\s*\)\s*\{\s*console\.warn\(\s*["\'][^"\']*containers/rid missing[^"\']*["\']\s*\)\s*;?\s*return\s*;?\s*\}',
        lambda m: m.group(0).replace("return", f"/* {MARK_A}: keep-going */\n      // return"),
        s,
        flags=re.I
    )
    n += k

    # Pattern 2: if(!ok) console.warn(...); return;
    s, k = re.subn(
        r'(if\s*\(\s*!ok\s*\)\s*console\.warn\(\s*["\'][^"\']*containers/rid missing[^"\']*["\']\s*\)\s*;?)\s*return\s*;?',
        r'\1\n      /* '+MARK_A+': keep-going (no return) */\n',
        s,
        flags=re.I
    )
    n += k

    # Pattern 3: any "gave up: containers/rid missing" followed by clearInterval+return in same block (loose)
    s, k = re.subn(
        r'(gave up:\s*containers/rid missing[^;\n]*["\']\s*\)\s*;[^{};\n]{0,180})\breturn\s*;',
        r'\1 /* '+MARK_A+': no-return */',
        s,
        flags=re.I
    )
    n += k

    # Mark
    s = s.rstrip() + f"\n/* {MARK_A}: patched_n={n} */\n"

    if s != orig:
        bak=backup(p, "dash_v6d_nogiveup")
        p.write_text(s, encoding="utf-8")
        print(f"[OK] dash-v6d patched: {p}  n={n}  backup={bak}")
        return True

    # still mark so we don't keep trying
    bak=backup(p, "dash_v6d_markonly")
    p.write_text(orig.rstrip()+f"\n/* {MARK_A}: no-match */\n", encoding="utf-8")
    print(f"[OK] dash-v6d mark-only (no match): {p}  backup={bak}")
    return True

# --------- (B) Inject: clear RUNS FAIL/degraded banners when runs fetch OK ----------
MARK_B="VSP_P0_CLEAR_RUNS_FAIL_ON_SUCCESS_V1"
INJECT_B=r"""
/* ===== VSP_P0_CLEAR_RUNS_FAIL_ON_SUCCESS_V1 =====
   Clear sticky "RUNS API FAIL" / "degraded (runs API 503)" when any /api/vsp/runs returns OK.
*/
(function(){
  try{
    if(window.__VSP_CLEAR_RUNS_FAIL_V1) return;
    window.__VSP_CLEAR_RUNS_FAIL_V1 = true;

    function _qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(e){ return []; } }

    function hideByText(rx){
      const nodes=_qsa("div,span,small,label,button,a");
      for(const el of nodes){
        const t=(el.textContent||"").trim();
        if(!t) continue;
        if(rx.test(t)){
          try{ el.style.display="none"; }catch(_e){}
        }
      }
    }

    function clearRunsFailUI(){
      // Banner variants
      hideByText(/RUNS\s*API\s*FAIL/i);
      hideByText(/degraded\s*\(runs\s*api\s*503\)/i);
      hideByText(/Error:\s*503\s*\/api\/vsp\/runs/i);

      // If you have specific containers, hide them too (safe if absent)
      const ids=["runs-api-fail","vsp-runs-fail","runs_fail_banner","vsp_runs_fail_banner"];
      for(const id of ids){
        const el=document.getElementById(id);
        if(el){ try{ el.style.display="none"; }catch(_e){} }
      }
    }

    // Wrap fetch (wrap the already-wrapped one) to observe success
    if(window.fetch && !window.__VSP_FETCH_OBS_RUNS_OK_V1){
      window.__VSP_FETCH_OBS_RUNS_OK_V1 = true;
      const orig = window.fetch.bind(window);
      window.fetch = async (input, init)=>{
        const r = await orig(input, init);
        try{
          let u="";
          try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_e){}
          if(u && u.includes("/api/vsp/runs") && r && r.ok){
            clearRunsFailUI();
          }
        }catch(_e){}
        return r;
      };
    }

    // extra safety: clear after load + after 2s (in case banners render after fetch)
    if(document.readyState==="loading"){
      document.addEventListener("DOMContentLoaded", ()=>setTimeout(clearRunsFailUI, 300));
    }else{
      setTimeout(clearRunsFailUI, 300);
    }
    setTimeout(clearRunsFailUI, 2000);
  }catch(_e){}
})();
"""

def inject_clear_runs_fail(p: Path):
    if not p.exists(): 
        print("[SKIP] missing:", p); 
        return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK_B in s:
        print("[SKIP] already:", p)
        return False
    bak=backup(p, "clear_runs_fail")
    p.write_text(s.rstrip()+"\n\n"+INJECT_B.strip()+"\n", encoding="utf-8")
    print(f"[OK] injected clear-runs-fail: {p}  backup={bak}")
    return True

changed=False
# dash patch in bundles
for fp in [Path("static/js/vsp_bundle_commercial_v2.js"), Path("static/js/vsp_bundle_commercial_v1.js")]:
    changed = patch_dash_v6d(fp) or changed

# inject banner clear into runs js + bundles (safe)
for fp in [Path("static/js/vsp_runs_tab_resolved_v1.js"),
           Path("static/js/vsp_bundle_commercial_v2.js"),
           Path("static/js/vsp_bundle_commercial_v1.js")]:
    changed = inject_clear_runs_fail(fp) or changed

print("[DONE] changed=", changed)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] Patch applied. Restart UI then Ctrl+F5 /runs and /vsp5"
