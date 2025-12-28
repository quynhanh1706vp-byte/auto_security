#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
MARK="VSP_P1_RELEASE_CARD_AUDITPACK_LATEST_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_rel_audit_${TS}"
echo "[BACKUP] ${JS}.bak_rel_audit_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap
p=Path("static/js/vsp_runs_quick_actions_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_RELEASE_CARD_AUDITPACK_LATEST_V1" in s:
    print("[SKIP] already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_AUDITPACK_LATEST_V1 =====================
   Add "Audit Pack (Latest)" into Current Release panel (Runs page).
   Uses /api/vsp/runs?limit=1 to resolve latest RID.
   Click => lite, Shift/Alt+Click => full.
============================================================================= */
(function(){
  if (window.__vsp_release_audit_latest_v1) return;
  window.__vsp_release_audit_latest_v1 = true;

  async function getLatestRid(){
    try{
      const r = await fetch('/api/vsp/runs?limit=1', {cache:'no-store'});
      const j = await r.json();
      const one = (j.runs && j.runs[0]) || {};
      return one.rid || one.run_id || '';
    }catch(e){ return ''; }
  }

  function auditLiteUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}&lite=1`; }
  function auditFullUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}`; }

  function dl(url){
    try{
      const a=document.createElement('a');
      a.href=url; a.target='_blank'; a.rel='noopener';
      a.style.display='none'; document.body.appendChild(a);
      a.click(); setTimeout(()=>a.remove(),250);
    }catch(e){}
  }

  function findReleasePanel(){
    // heuristics: look for a box containing "Current Release"
    const nodes = Array.from(document.querySelectorAll('*'));
    for(const n of nodes){
      const tx = (n.textContent||'').trim();
      if(tx === 'Current Release' || tx.includes('Current Release')){
        // pick container: nearest card-like div
        return n.closest('div') || n.parentElement || null;
      }
    }
    return null;
  }

  function injectBtn(panel, rid){
    if(!panel || !rid) return;
    if(panel.querySelector && panel.querySelector('[data-rel-audit-latest="1"]')) return;

    const wrap=document.createElement('div');
    wrap.style.cssText='margin-top:8px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;';
    const b=document.createElement('button');
    b.type='button';
    b.className='vsp-btn vsp-btn-sm';
    b.textContent='Audit Pack (Latest)';
    b.title='Click: Lite | Shift/Alt+Click: Full';
    b.setAttribute('data-rel-audit-latest','1');

    b.addEventListener('click', (ev)=>{
      ev.preventDefault(); ev.stopPropagation();
      const full = !!(ev.shiftKey || ev.altKey);
      dl(full ? auditFullUrl(rid) : auditLiteUrl(rid));
    });

    const meta=document.createElement('span');
    meta.style.cssText='opacity:.85;font-size:12px;';
    meta.textContent=`RID: ${rid}`;

    wrap.appendChild(b);
    wrap.appendChild(meta);

    panel.appendChild(wrap);
  }

  async function boot(){
    const rid = await getLatestRid();
    if(!rid) return;
    const panel = findReleasePanel();
    if(!panel) return;
    injectBtn(panel, rid);
  }

  setTimeout(boot, 450);
})();
""").strip("\n")

s = s + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended release card audit latest")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Reload /runs. You should see 'Audit Pack (Latest)' in Current Release panel."
