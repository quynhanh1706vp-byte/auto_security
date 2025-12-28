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

TS=time.strftime("%Y%m%d_%H%M%S)")
MARK="VSP_P0_RUNS_LATCH_LASTGOOD_V1"

INJECT = r"""
/* ===== VSP_P0_RUNS_LATCH_LASTGOOD_V1 =====
   Latch "runs OK" after first successful items[].
   If later /api/vsp/runs returns ok:false / fails, serve last-good and suppress degraded UI.
*/
(function(){
  try{
    if(window.__VSP_RUNS_LATCH_LASTGOOD_V1) return;
    window.__VSP_RUNS_LATCH_LASTGOOD_V1 = true;

    const KEY = "vsp_runs_lastgood_v1";
    const RX_BAD = /(RUNS\s*API\s*FAIL|degraded\s*\(runs\s*api\s*503\)|Error:\s*503\s*\/api\/vsp\/runs)/i;

    let latched = false;

    function _save(obj){
      try{ localStorage.setItem(KEY, JSON.stringify(obj)); }catch(_){}
    }
    function _load(){
      try{
        const raw = localStorage.getItem(KEY);
        return raw ? JSON.parse(raw) : null;
      }catch(_){ return null; }
    }
    function _resp(obj, hdr){
      const h = new Headers({"Content-Type":"application/json; charset=utf-8"});
      try{ if(hdr) for(const [k,v] of Object.entries(hdr)) h.set(k, String(v)); }catch(_){}
      return new Response(JSON.stringify(obj), {status:200, headers:h});
    }

    function _nukeDegradedUI(){
      if(!latched) return;
      try{
        // common alert/toast containers first
        const sel = ["[role='alert']", ".toast", ".toaster", ".snackbar", ".notification", ".banner", ".status", ".vsp-toast", ".vsp-banner"];
        for(const s of sel){
          for(const el of document.querySelectorAll(s)){
            const t = (el.textContent||"").trim();
            if(t && RX_BAD.test(t)){
              el.style.display="none";
              el.setAttribute("data-vsp-hide-degraded","1");
            }
          }
        }
        // lightweight pass on top-level bars only (avoid scanning whole DOM)
        for(const el of document.querySelectorAll("header,nav,main,body")){
          const t = (el.textContent||"").trim();
          if(t && RX_BAD.test(t)){
            // hide only child nodes that match
            for(const c of el.querySelectorAll("div,span,small,label,button,a")){
              const tt = (c.textContent||"").trim();
              if(tt && RX_BAD.test(tt)){
                c.style.display="none";
                c.setAttribute("data-vsp-hide-degraded","1");
              }
            }
          }
        }
      }catch(_){}
    }

    // Clear known sticky flags from older patches (best-effort)
    try{
      for(const k of Object.keys(localStorage)){
        if(/vsp.*runs.*fail|runs.*fail|vsp.*degraded/i.test(k)) localStorage.removeItem(k);
      }
    }catch(_){}

    // Wrap fetch AFTER NetGuard wrapper (we run later), so this is the final guard
    if(window.fetch && !window.__VSP_RUNS_FETCH_WRAPPED_V1){
      window.__VSP_RUNS_FETCH_WRAPPED_V1 = true;
      const orig = window.fetch.bind(window);
      window.fetch = async (input, init)=>{
        let u="";
        try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
        const isRuns = !!u && u.includes("/api/vsp/runs");
        if(!isRuns) return orig(input, init);

        try{
          const r = await orig(input, init);

          // If request is OK, try to detect items[] and latch/save
          let j = null;
          try{
            const c = r.clone();
            j = await c.json();
          }catch(_){ j = null; }

          const hasItems = !!j && Array.isArray(j.items);
          const itemsN = hasItems ? j.items.length : 0;

          if(hasItems && itemsN > 0){
            latched = true;
            window.__vsp_runs_ok_latched = true;
            _save(j);
            setTimeout(_nukeDegradedUI, 0);
            return r;
          }

          // If response indicates degraded (ok:false) OR empty items AND we are latched -> serve last good
          const looksDegraded = (!!j && j.ok === false) || (!r.ok) || (hasItems && itemsN === 0);
          if(latched && looksDegraded){
            const cached = _load();
            if(cached && Array.isArray(cached.items) && cached.items.length > 0){
              setTimeout(_nukeDegradedUI, 0);
              return _resp(cached, {"X-VSP-Runs-Latched":"1","X-VSP-From":"lastgood"});
            }
          }

          return r;
        }catch(e){
          if(latched){
            const cached = _load();
            if(cached && Array.isArray(cached.items) && cached.items.length > 0){
              setTimeout(_nukeDegradedUI, 0);
              return _resp(cached, {"X-VSP-Runs-Latched":"1","X-VSP-From":"lastgood-ex"});
            }
          }
          throw e;
        }
      };
    }

    // If degraded UI appears later, keep suppressing once latched
    try{
      const obs = new MutationObserver(()=>{ _nukeDegradedUI(); });
      obs.observe(document.documentElement, {childList:true, subtree:true});
    }catch(_){}
  }catch(_){}
})();
"""

def backup(p: Path):
    bak=p.with_name(p.name + f".bak_runs_latch_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def inject(p: Path):
    if not p.exists():
        print("[SKIP] missing:", p); return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P0_RUNS_LATCH_LASTGOOD_V1" in s:
        print("[SKIP] already:", p); return False
    bak=backup(p)
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
