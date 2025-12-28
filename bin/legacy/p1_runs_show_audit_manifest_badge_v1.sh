#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
MARK="VSP_P1_RUNS_AUDIT_BADGE_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditbadge_${TS}"
echo "[BACKUP] ${JS}.bak_auditbadge_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_runs_quick_actions_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_RUNS_AUDIT_BADGE_V1" in s:
    print("[SKIP] audit badge already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P1_RUNS_AUDIT_BADGE_V1 =====================
   Show Audit manifest badge per row using /api/vsp/audit_pack_manifest
   - Badge: ✓inc / ✗miss / ⚠err
   - Lite-only fetch (fast): lite=1
   - Tooltip: show first few error paths
============================================================================= */
(function(){
  if (window.__vsp_audit_badge_v1) return;
  window.__vsp_audit_badge_v1 = true;

  const cache = new Map(); // rid -> manifest json
  const inflight = new Map();

  function mkBadge(j){
    const inc = j.included_count ?? 0;
    const miss = j.missing_count ?? 0;
    const err = j.errors_count ?? 0;

    const b = document.createElement('span');
    b.className = 'vsp-audit-badge-v1';
    b.style.cssText = [
      'display:inline-flex','align-items:center','gap:6px',
      'margin-left:8px','padding:2px 8px','border-radius:999px',
      'font-size:12px','line-height:18px',
      'border:1px solid rgba(120,160,255,.25)',
      'background:rgba(8,14,28,.55)','color:#cfe3ff'
    ].join(';');

    b.textContent = `Audit ✓${inc} ✗${miss} ⚠${err}`;

    // tooltip
    try{
      const errs = (j.errors || []).slice(0,4).map(x=>x.path).filter(Boolean);
      const missp = (j.missing || []).slice(0,4).map(x=>x.path).filter(Boolean);
      let tip = `Audit manifest (lite)\n✓ included: ${inc}\n✗ missing: ${miss}\n⚠ errors: ${err}`;
      if (errs.length) tip += `\n\nErrors:\n- ` + errs.join('\n- ');
      if (missp.length) tip += `\n\nMissing:\n- ` + missp.join('\n- ');
      b.title = tip;
    }catch(e){}
    return b;
  }

  async function fetchManifest(rid){
    if(cache.has(rid)) return cache.get(rid);
    if(inflight.has(rid)) return inflight.get(rid);

    const p = (async ()=>{
      try{
        const u = `/api/vsp/audit_pack_manifest?rid=${encodeURIComponent(rid)}&lite=1`;
        const r = await fetch(u, {cache:'no-store'});
        const j = await r.json();
        cache.set(rid, j);
        return j;
      }catch(e){
        const j = {ok:false, err:String(e), included_count:0, missing_count:0, errors_count:0};
        cache.set(rid, j);
        return j;
      }finally{
        inflight.delete(rid);
      }
    })();

    inflight.set(rid, p);
    return p;
  }

  function resolveRid(node){
    if(!node) return '';
    const el = node.closest && (node.closest('[data-rid]') || node.closest('[data-run-id]'));
    if(el && el.getAttribute){
      return el.getAttribute('data-rid') || el.getAttribute('data-run-id') || '';
    }
    // fallback: scan up
    let p=node;
    for(let i=0;i<6 && p; i++){
      if(p.getAttribute){
        const r = p.getAttribute('data-rid') || p.getAttribute('data-run-id');
        if(r) return r;
      }
      p = p.parentElement;
    }
    // try find rid text
    try{
      const tr = node.closest && node.closest('tr');
      if(tr){
        const txt = tr.innerText || '';
        const m = txt.match(/\b([A-Za-z]+_[A-Za-z0-9]+_[0-9]{8}_[0-9]{6,})\b/);
        if(m && m[1]) return m[1];
      }
    }catch(e){}
    return '';
  }

  function placeBadgeNearAuditButton(btn, badge){
    // Put badge right after the button group
    try{
      const parent = btn.parentElement || btn;
      if(parent.querySelector && parent.querySelector('.vsp-audit-badge-v1')) return;
      parent.appendChild(badge);
    }catch(e){}
  }

  async function scanAndAttach(){
    const buttons = Array.from(document.querySelectorAll('button'))
      .filter(b => ((b.textContent||'').trim().toLowerCase() === 'audit pack') || (b.getAttribute('data-act')||'').toLowerCase().includes('audit'));

    let attached = 0;
    for(const btn of buttons){
      if(btn.__vsp_badge_done) continue;
      const rid = btn.getAttribute('data-rid') || resolveRid(btn);
      if(!rid) continue;

      btn.__vsp_badge_done = true;
      const j = await fetchManifest(rid);
      const badge = mkBadge(j);
      placeBadgeNearAuditButton(btn, badge);
      attached++;
    }
    if(attached>0 && !window.__vsp_audit_badge_log_once){
      window.__vsp_audit_badge_log_once = true;
      console.log('[VSP][Runs] audit badge attached:', attached);
    }
  }

  // Observe rerenders/pagination
  try{
    const obs = new MutationObserver(()=>{
      if(window.__vsp_audit_badge_t) return;
      window.__vsp_audit_badge_t = setTimeout(()=>{
        window.__vsp_audit_badge_t = null;
        scanAndAttach();
      }, 180);
    });
    obs.observe(document.body, {childList:true, subtree:true});
  }catch(e){}

  setTimeout(scanAndAttach, 400);
  setTimeout(scanAndAttach, 1200);
})();
""").strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended audit badge v1")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Reload /runs. You should see 'Audit ✓inc ✗miss ⚠err' badge next to Audit Pack."
