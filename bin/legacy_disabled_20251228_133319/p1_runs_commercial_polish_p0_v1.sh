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
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_RUNS_COMMERCIAL_POLISH_V1"

# 1) Replace all /vsp5/runs -> /runs across templates + js
roots = [Path("templates"), Path("static/js")]
patched_files=[]

def backup(p: Path, tag: str):
    bak = p.with_name(p.name + f".bak_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def replace_path(p: Path):
    s = p.read_text(encoding="utf-8", errors="replace")
    if "/vsp5/runs" not in s:
        return False
    bak = backup(p, "runs_pathfix")
    s2 = s.replace("/vsp5/runs", "/runs")
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] pathfix: {p}  backup={bak}")
    return True

for root in roots:
    if not root.exists():
        continue
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.suffix.lower() not in (".html",".js"):
            continue
        try:
            if replace_path(p):
                patched_files.append(str(p))
        except Exception as e:
            print("[WARN] skip", p, e)

# 2) Inject JS snippet to enforce /runs default no-filter + limit=50 + clear degraded badge on success
INJECT = r"""
/* ===== VSP_P0_RUNS_COMMERCIAL_POLISH_V1 =====
   - /runs default: no-filter (has_*) + limit=50
   - clear sticky degraded badge if /api/vsp/runs returns OK
*/
(function(){
  try{
    function onRunsPage(){
      try{
        const p=(location && location.pathname) ? location.pathname : "";
        return p === "/runs" || p.startsWith("/runs/");
      }catch(_e){ return false; }
    }
    if(!onRunsPage()) return;
    if(window.__VSP_RUNS_POLISH_P0_V1) return;
    window.__VSP_RUNS_POLISH_P0_V1 = true;

    function _qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(e){ return []; } }
    function _qs(sel, root){ try{ return (root||document).querySelector(sel); }catch(e){ return null; } }

    function clearLocalStorageFilters(){
      try{
        const ks = Object.keys(localStorage||{});
        for(const k of ks){
          const kl=(k||"").toLowerCase();
          if(
            kl.includes("runs_filter") || kl.includes("vsp_runs") ||
            kl.startsWith("has_") || kl.includes("has_json") || kl.includes("has_sum") || kl.includes("has_summary") ||
            kl.includes("has_html") || kl.includes("has_csv") || kl.includes("has_sarif") ||
            kl.includes("only_with") || kl.includes("artifact") || kl.includes("runs_limit")
          ){
            try{ localStorage.removeItem(k); }catch(_e){}
          }
        }
      }catch(_e){}
    }

    function forceNoFilter(root){
      // uncheck any "has_*" checkboxes (id/name/label)
      const cbs=_qsa('input[type="checkbox"]', root);
      for(const el of cbs){
        const id=(el.id||"").toLowerCase();
        const nm=(el.name||"").toLowerCase();
        const lb=(el.getAttribute("aria-label")||"").toLowerCase();
        const t=id+" "+nm+" "+lb;
        const isHas = t.startsWith("has_") || t.includes("has_json") || t.includes("has_sum") || t.includes("has_summary") ||
                      t.includes("has_html") || t.includes("has_csv") || t.includes("has_sarif") ||
                      t.includes("only_with") || t.includes("artifact");
        if(!isHas) continue;
        try{
          if(el.checked) el.checked=false;
          if(el.hasAttribute("checked")) el.removeAttribute("checked");
        }catch(_e){}
      }

      // set limit to 50 if control exists
      const limitEls=[
        document.getElementById("limit"),
        document.getElementById("runs-limit"),
        document.getElementById("vsp-runs-limit"),
        _qs('input[name="limit"]'),
        _qs('select[name="limit"]'),
      ].filter(Boolean);

      for(const el of limitEls){
        try{
          if(el.tagName==="SELECT"){
            const opt=Array.from(el.options||[]).find(o=>String(o.value)==="50");
            if(opt) el.value="50";
          }else{
            el.value="50";
          }
        }catch(_e){}
      }
    }

    function hideDegradedBadge(){
      // hide any element showing degraded runs api 503
      const nodes=_qsa("div,span,small,label,button");
      for(const el of nodes){
        const t=(el.textContent||"").toLowerCase();
        if(t.includes("degraded") && t.includes("runs") && t.includes("api")){
          try{ el.style.display="none"; }catch(_e){}
        }
      }
    }

    async function clearDegradedIfRunsOk(){
      try{
        const res=await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
        if(res && res.ok){
          hideDegradedBadge();
        }
      }catch(_e){}
    }

    function boot(){
      clearLocalStorageFilters();
      forceNoFilter(document);

      // Observe late-render checkboxes and force off
      const obs=new MutationObserver((muts)=>{
        for(const m of muts){
          for(const n of Array.from(m.addedNodes||[])){
            if(n && n.querySelectorAll) forceNoFilter(n);
          }
        }
      });
      try{ obs.observe(document.documentElement||document.body, {childList:true, subtree:true}); }catch(_e){}

      // Clear degraded badge when API OK (a few attempts)
      setTimeout(clearDegradedIfRunsOk, 600);
      setTimeout(clearDegradedIfRunsOk, 2200);
      setTimeout(clearDegradedIfRunsOk, 5200);
    }

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }catch(_e){}
})();
"""

for p in [Path("static/js/vsp_runs_tab_resolved_v1.js"),
          Path("static/js/vsp_bundle_commercial_v2.js"),
          Path("static/js/vsp_bundle_commercial_v1.js")]:
    if not p.exists():
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print(f"[SKIP] already injected {MARK}: {p}")
        continue
    bak=backup(p, "runs_polish")
    p.write_text(s.rstrip()+"\n\n"+INJECT.strip()+"\n", encoding="utf-8")
    print(f"[OK] injected {MARK}: {p}  backup={bak}")

print("[DONE] pathfix_patched=", len(patched_files))
PY

# node syntax check
for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] P0 runs commercial polish applied."
echo "NEXT: restart UI (gunicorn) then Ctrl+F5 /runs and /vsp5"
