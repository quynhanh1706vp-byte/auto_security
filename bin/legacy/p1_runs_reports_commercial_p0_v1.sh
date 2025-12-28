#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# Candidate JS files (ưu tiên theo thứ tự)
CAND_JS=(
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
)

# Candidate templates (để hạ console warn rid_latest nếu có inline)
CAND_TPL=(
  "templates/vsp_5tabs_enterprise_v2.html"
  "templates/vsp_dashboard_2025.html"
  "templates/vsp_4tabs_commercial_v1.html"
)

python3 - <<'PY'
from pathlib import Path
import re, time

TS = time.strftime("%Y%m%d_%H%M%S")

cand_js = [Path(p) for p in [
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
]]
cand_tpl = [Path(p) for p in [
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_4tabs_commercial_v1.html",
]]

MARK = "VSP_P0_RUNS_REPORTS_COMMERCIAL_POLISH_V1"
INJECT = r"""
/* ===== VSP_P0_RUNS_REPORTS_COMMERCIAL_POLISH_V1 =====
   - Default no-filter + limit=50
   - Bind row click -> localStorage vsp_rid_selected_v2
   - Fix rid_latest fetch order + reduce noisy warn
   Safe: no-op if elements not present.
*/
(function(){
  try{
    function _qs(sel, root){ try{ return (root||document).querySelector(sel);}catch(e){return null;} }
    function _qsa(sel, root){ try{ return Array.from((root||document).querySelectorAll(sel));}catch(e){return [];} }

    function vspSetSelectedRid(rid){
      if(!rid) return;
      try{ localStorage.setItem('vsp_rid_selected_v2', rid); }catch(e){}
      try{ localStorage.setItem('vsp_rid_selected', rid); }catch(e){} // compat
      // optional badges (nếu có)
      const badge =
        document.getElementById('vsp-selected-rid-badge') ||
        document.getElementById('vsp-rid-selected') ||
        document.getElementById('vsp-rid-latest') ||
        _qs('[data-vsp-selected-rid]') ||
        _qs('[data-selected-rid]');
      if(badge){
        try{ badge.textContent = rid; }catch(e){}
      }
    }

    function vspRunsDefaultNoFilterAndLimit(){
      // cố gắng set default limit=50 nếu có input/select
      const limitEls = [
        document.getElementById('limit'),
        document.getElementById('runs-limit'),
        document.getElementById('vsp-runs-limit'),
        _qs('input[name="limit"]'),
        _qs('select[name="limit"]'),
      ].filter(Boolean);

      for(const el of limitEls){
        try{
          if(el.tagName === 'SELECT'){
            // chọn option 50 nếu có
            const opt = Array.from(el.options||[]).find(o => String(o.value) === '50');
            if(opt){ el.value='50'; }
          }else{
            // input
            if(!el.value || String(el.value).trim()==='' || String(el.value)==='20' || String(el.value)==='10'){
              el.value = '50';
            }
          }
        }catch(e){}
      }

      // đảm bảo default không tick filter
      const ids = [
        'has_json','has_summary','has_html','has_csv','has_sarif',
        'filter','filter_on','hide_empty','only_with_artifacts'
      ];
      for(const id of ids){
        const el = document.getElementById(id);
        if(el && (el.type === 'checkbox' || el.type === 'radio')){
          try{ el.checked = false; }catch(e){}
        }
      }
      // các checkbox theo name (phòng khi id khác)
      _qsa('input[type="checkbox"][name^="has_"], input[type="checkbox"][name*="has"]')
        .forEach(el => { try{ el.checked = false; }catch(e){} });
    }

    function vspBindRidRowClick(){
      // delegate click: tìm ancestor có data-run-id/data-rid
      document.addEventListener('click', function(e){
        const t = e.target;
        if(!t || !t.closest) return;
        const holder = t.closest('[data-run-id],[data-rid],[data-runid],tr[data-run-id],tr[data-rid],tr[data-runid]');
        if(!holder) return;
        const rid = holder.getAttribute('data-run-id') || holder.getAttribute('data-rid') || holder.getAttribute('data-runid');
        if(rid) vspSetSelectedRid(rid);
      }, true);
    }

    async function vspFixRidLatestAfterRunsLoad(){
      // chỉ fetch 1 lần, nhẹ
      try{
        const res = await fetch('/api/vsp/runs?limit=1');
        if(!res.ok) return;
        const j = await res.json();
        const rid = (j && j.items && j.items[0] && (j.items[0].run_id || j.items[0].rid)) || j.rid_latest;
        if(rid) vspSetSelectedRid(rid);
      }catch(e){}
    }

    function boot(){
      vspRunsDefaultNoFilterAndLimit();
      vspBindRidRowClick();
      // rid_latest: chạy async sau, tránh log N/A quá sớm
      setTimeout(vspFixRidLatestAfterRunsLoad, 350);
    }

    if(document.readyState === 'loading'){
      document.addEventListener('DOMContentLoaded', boot);
    }else{
      boot();
    }
  }catch(_e){}
})();
"""

def backup(p: Path):
    b = p.with_name(p.name + f".bak_p0_runs_reports_{TS}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[BACKUP] {b}")

def patch_js(p: Path):
    if not p.exists():
        return False
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s
    changed = False

    # 1) Nếu có slice(0,20) thì nâng lên 50 (an toàn hơn remove)
    s2, n1 = re.subn(r"\.slice\(\s*0\s*,\s*20\s*\)", ".slice(0, 50)", s)
    if n1:
        s = s2
        changed = True

    # 2) Nếu có log warn rid_latest thì hạ xuống debug (giảm “đỏ” console)
    s2, n2 = re.subn(r"console\.warn\(([^)]*rid_latest[^)]*)\)", r"console.debug(\1)", s)
    if n2:
        s = s2
        changed = True

    # 3) Inject snippet nếu chưa có
    if MARK not in s:
        s = s.rstrip() + "\n\n" + INJECT.strip() + "\n"
        changed = True

    if changed and s != orig:
        backup(p)
        p.write_text(s, encoding="utf-8")
        print(f"[OK] patched JS: {p} (slice20->{n1}, warn->debug:{n2}, injected:{MARK not in orig})")
        return True
    else:
        print(f"[SKIP] JS unchanged: {p}")
        return False

def patch_tpl(p: Path):
    if not p.exists():
        return False
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s
    changed = False

    # hạ warn rid_latest nếu có inline script log
    s2, n = re.subn(r"console\.warn\(([^)]*rid_latest[^)]*)\)", r"console.debug(\1)", s)
    if n:
        s = s2
        changed = True

    if changed and s != orig:
        backup(p)
        p.write_text(s, encoding="utf-8")
        print(f"[OK] patched TPL: {p} (warn->debug:{n})")
        return True
    else:
        print(f"[SKIP] TPL unchanged: {p}")
        return False

patched_any = False
for f in cand_js:
    patched_any = patch_js(f) or patched_any

for f in cand_tpl:
    patched_any = patch_tpl(f) or patched_any

print("[DONE] patched_any=", patched_any)
PY

# node syntax check nếu có
for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] P0 runs&reports commercial polish applied."
echo "NEXT: restart UI service (if needed) + Ctrl+F5 /vsp5"
