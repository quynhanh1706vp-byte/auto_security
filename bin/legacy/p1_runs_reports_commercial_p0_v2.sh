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
MARK="VSP_P0_RUN_BADGE_AND_FILTER_RESET_V1"

INJECT=r"""
/* ===== VSP_P0_RUN_BADGE_AND_FILTER_RESET_V1 =====
   Goals:
   - Force default Runs tab = no-filter (clear persisted has/filter keys) + limit=50
   - Update header badge "ENV: ... RUN: ..." even if element has no id
   - Refresh runs list once after reset (best-effort)
*/
(function(){
  try{
    function _qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel)); }catch(e){ return []; } }
    function _qs(sel, root){ try{ return (root||document).querySelector(sel); }catch(e){ return null; } }

    function vspUpdateRunBadge(rid){
      if(!rid) return;
      // 1) try known ids first
      const known = [
        'vsp-run-badge','vsp-run-id-badge','vsp-selected-run','vsp-selected-rid-badge',
        'vsp-rid-selected','vsp-rid-latest'
      ];
      for(const id of known){
        const el=document.getElementById(id);
        if(el){ try{ el.textContent = String(el.textContent||'').replace(/RUN:\s*[^|]+/i, 'RUN: '+rid); if(el.textContent===String(el.textContent||'')) el.textContent = rid; }catch(e){} return; }
      }

      // 2) heuristic: find any small badge-like element containing "ENV:" and "RUN:"
      const nodes=_qsa('span,div,small,label');
      for(const el of nodes){
        const t=(el.textContent||'').trim();
        if(!t) continue;
        if(t.includes('ENV:') && t.includes('RUN:')){
          try{
            el.textContent = t.replace(/RUN:\s*[^|]+/i, 'RUN: '+rid);
          }catch(e){}
          return;
        }
      }
    }

    function vspSetSelectedRid(rid){
      if(!rid) return;
      try{ localStorage.setItem('vsp_rid_selected_v2', rid); }catch(e){}
      try{ localStorage.setItem('vsp_rid_selected', rid); }catch(e){}
      vspUpdateRunBadge(rid);
    }

    function vspClearRunsFilterState(){
      // Clear persisted filters that cause "Showing 7 of 298"
      try{
        const ks = Object.keys(localStorage||{});
        for(const k of ks){
          const kl = (k||'').toLowerCase();
          if(
            kl.includes('runs_filter') ||
            kl.includes('vsp_runs') ||
            kl.includes('has_json') || kl.includes('has_summary') || kl.includes('has_html') || kl.includes('has_csv') || kl.includes('has_sarif') ||
            kl.startswith?.('has_') ||
            kl.includes('only_with') ||
            kl.includes('filter_has') ||
            kl.includes('filter_artifact') ||
            kl.includes('runs_limit')
          ){
            try{ localStorage.removeItem(k); }catch(e){}
          }
        }
      }catch(e){}

      // Uncheck any has_* checkbox by id or name
      _qsa('input[type="checkbox"]').forEach(el=>{
        const id=(el.id||'').toLowerCase();
        const nm=(el.name||'').toLowerCase();
        if(id.startsWith('has_') || nm.startsWith('has_') || id.includes('only_with') || nm.includes('only_with')){
          try{ el.checked=false; }catch(e){}
        }
      });

      // Set limit to 50 if there is a limit control
      const limitEls = [
        document.getElementById('limit'),
        document.getElementById('runs-limit'),
        document.getElementById('vsp-runs-limit'),
        _qs('input[name="limit"]'),
        _qs('select[name="limit"]'),
      ].filter(Boolean);

      for(const el of limitEls){
        try{
          if(el.tagName==='SELECT'){
            const opt=Array.from(el.options||[]).find(o=>String(o.value)==='50');
            if(opt) el.value='50';
          }else{
            el.value='50';
          }
        }catch(e){}
      }

      // Clear search box if any
      ['q','runs-q','vsp-runs-q','search','runs-search'].forEach(id=>{
        const el=document.getElementById(id);
        if(el && (el.tagName==='INPUT' || el.tagName==='TEXTAREA')){
          try{ el.value=''; }catch(e){}
        }
      });
    }

    async function vspFixRidLatestAfterRunsLoad(){
      try{
        const res=await fetch('/api/vsp/runs?limit=1');
        if(!res.ok) return;
        const j=await res.json();
        const rid=(j && j.items && j.items[0] && (j.items[0].run_id || j.items[0].rid)) || j.rid_latest;
        if(rid) vspSetSelectedRid(rid);
      }catch(e){}
    }

    function vspBestEffortRefreshRuns(){
      // click a refresh button if exists
      const btn =
        document.getElementById('runs-refresh') ||
        _qs('[data-action="refresh-runs"]') ||
        _qs('[data-vsp-refresh-runs]');

      if(btn && btn.click){
        try{ btn.click(); return; }catch(e){}
      }
      // fallback: call common global if present
      const fns = ['refreshRuns','loadRuns','initRunsTab','vspRunsRefresh'];
      for(const n of fns){
        try{
          if(typeof window[n] === 'function'){ window[n](); return; }
        }catch(e){}
      }
    }

    function boot(){
      vspClearRunsFilterState();
      // rid_latest must be set AFTER reset to avoid "N/A"
      setTimeout(vspFixRidLatestAfterRunsLoad, 350);
      // refresh runs after filter reset
      setTimeout(vspBestEffortRefreshRuns, 650);
    }

    if(document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot);
    else boot();
  }catch(_e){}
})();
"""

def backup(p: Path):
    b=p.with_name(p.name+f".bak_p0_v2_{TS}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[BACKUP] {b}")

def patch(p: Path):
    if not p.exists(): return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print(f"[SKIP] already has {MARK}: {p}")
        return False
    backup(p)
    s2=s.rstrip()+"\n\n"+INJECT.strip()+"\n"
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] injected {MARK}: {p}")
    return True

patched=False
for fp in [
  Path("static/js/vsp_runs_tab_resolved_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
]:
    patched = patch(fp) or patched

print("[DONE] patched_any=", patched)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] P0 v2 applied. Restart UI if needed, then Ctrl+F5 /vsp5"
