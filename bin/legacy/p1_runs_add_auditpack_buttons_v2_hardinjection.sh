#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
MARK="VSP_P1_RUNS_AUDITPACK_V2_HARDINJECT"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditv2_${TS}"
echo "[BACKUP] ${JS}.bak_auditv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RUNS_AUDITPACK_V2_HARDINJECT" in s:
    print("[SKIP] v2 already present")
    raise SystemExit(0)

# Insert helpers near top inside IIFE
m = re.search(r"\(\(\)\s*=>\s*\{", s)
if not m:
    print("[ERR] cannot find IIFE start")
    raise SystemExit(2)

helpers = textwrap.dedent(r"""
/* ===================== VSP_P1_RUNS_AUDITPACK_V2_HARDINJECT =====================
   Guarantees Audit Pack buttons appear even if template changes.
   - Injects buttons into each run card/row action area post-render.
   - Robust RID resolver: data-rid, data-run-id, closest JSON blob, window.__vsp_runs cache.
   - Safe download via <a> click; simple toast.
============================================================================= */
const __vsp_auditpack_v2 = {installed:true};

function vspToast(msg){
  try{
    let t=document.getElementById('vsp_toast_v2');
    if(!t){
      t=document.createElement('div');
      t.id='vsp_toast_v2';
      t.style.cssText='position:fixed;right:16px;bottom:16px;z-index:99999;padding:10px 12px;border-radius:10px;background:#0b1220;color:#cfe3ff;border:1px solid rgba(120,160,255,.25);box-shadow:0 10px 30px rgba(0,0,0,.45);font:13px/1.3 system-ui;opacity:.0;transition:opacity .15s ease';
      document.body.appendChild(t);
    }
    t.textContent=msg;
    t.style.opacity='1';
    clearTimeout(t.__tm);
    t.__tm=setTimeout(()=>{t.style.opacity='0';}, 1400);
  }catch(e){}
}

function vspDownload(url){
  try{
    const a=document.createElement('a');
    a.href=url; a.target='_blank'; a.rel='noopener';
    a.style.display='none';
    document.body.appendChild(a);
    a.click();
    setTimeout(()=>a.remove(), 250);
  }catch(e){
    try{ window.open(url, '_blank', 'noopener'); }catch(_){}
  }
}

function vspAuditPackLiteUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}&lite=1`; }
function vspAuditPackFullUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}`; }

function vspResolveRidFromNode(node){
  if(!node) return '';
  // 1) dataset attrs
  let el=node.closest('[data-rid]') || node.closest('[data-run-id]') || node;
  if(el && el.getAttribute){
    const r = el.getAttribute('data-rid') || el.getAttribute('data-run-id');
    if(r) return r;
  }
  // 2) look for any element with rid attribute nearby
  let p=node;
  for(let i=0;i<5 && p; i++){
    if(p.getAttribute){
      const rr = p.getAttribute('data-rid') || p.getAttribute('data-run-id');
      if(rr) return rr;
    }
    p = p.parentElement;
  }
  // 3) try parse embedded JSON (if any)
  try{
    const jn = node.closest('[data-run]') || node.closest('[data-json]');
    if(jn){
      const raw = jn.getAttribute('data-run') || jn.getAttribute('data-json');
      if(raw && raw.trim().startsWith('{')){
        const obj = JSON.parse(raw);
        return obj.rid || obj.run_id || obj.id || '';
      }
    }
  }catch(e){}
  // 4) fallback: if global runs cache exists
  try{
    if(window.__vsp_runs_last && Array.isArray(window.__vsp_runs_last) && window.__vsp_runs_last.length){
      const one = window.__vsp_runs_last[0];
      return (one && (one.rid || one.run_id)) || '';
    }
  }catch(e){}
  return '';
}

function vspMakeAuditBtns(rid){
  const wrap=document.createElement('span');
  wrap.className='vsp-auditpack-wrap';
  wrap.style.cssText='display:inline-flex;gap:6px;align-items:center;margin-left:6px;';
  const mk=(label, act)=>{
    const b=document.createElement('button');
    b.type='button';
    b.className='vsp-btn vsp-btn-sm';
    b.setAttribute('data-act', act);
    b.setAttribute('data-rid', rid);
    b.textContent=label;
    b.title=(act==='audit_lite')?'Audit evidence pack (lite)':'Audit evidence pack (full)';
    return b;
  };
  wrap.appendChild(mk('Audit Lite','audit_lite'));
  wrap.appendChild(mk('Audit Full','audit_full'));
  return wrap;
}

function vspInjectAuditButtons(){
  // Find likely action containers in runs page
  const containers = []
    .concat(Array.from(document.querySelectorAll('.vsp-actions')))
    .concat(Array.from(document.querySelectorAll('[data-actions]')))
    .concat(Array.from(document.querySelectorAll('.actions')))
    .concat(Array.from(document.querySelectorAll('td:last-child')))
    .filter(Boolean);

  let injected=0;
  containers.forEach(c=>{
    // avoid injecting into header/footer
    if(!c || c.closest('thead')) return;
    if(c.querySelector && c.querySelector('.vsp-auditpack-wrap')) return;

    // resolve rid using closest run row/card
    const rid = vspResolveRidFromNode(c);
    if(!rid) return;

    // Insert at end of container
    try{
      c.appendChild(vspMakeAuditBtns(rid));
      injected++;
    }catch(e){}
  });

  if(injected>0){
    // console hint only once
    if(!window.__vsp_auditpack_v2_injected_once){
      window.__vsp_auditpack_v2_injected_once=true;
      console.log('[VSP][Runs] AuditPack v2 injected:', injected);
    }
  }
}

function vspAuditPackInitObserver(){
  // Observe DOM changes for runs list re-render/pagination
  try{
    const root = document.body;
    const obs = new MutationObserver(()=>{
      if(window.__vsp_auditpack_v2_t) return;
      window.__vsp_auditpack_v2_t = setTimeout(()=>{
        window.__vsp_auditpack_v2_t = null;
        vspInjectAuditButtons();
      }, 120);
    });
    obs.observe(root, {childList:true, subtree:true});
    // initial
    setTimeout(vspInjectAuditButtons, 200);
    setTimeout(vspInjectAuditButtons, 900);
  }catch(e){}
}

// Click delegation (robust)
document.addEventListener('click', (ev)=>{
  const t = ev.target;
  if(!t || !t.getAttribute) return;
  const act = t.getAttribute('data-act');
  if(act !== 'audit_lite' && act !== 'audit_full') return;

  const rid = t.getAttribute('data-rid') || vspResolveRidFromNode(t);
  if(!rid){
    vspToast('AuditPack: missing RID');
    return;
  }

  ev.preventDefault(); ev.stopPropagation();

  // prevent rapid double click
  if(t.__busy) return;
  t.__busy = true;
  t.disabled = true;
  vspToast('Downloading audit pack…');

  const url = (act === 'audit_lite') ? vspAuditPackLiteUrl(rid) : vspAuditPackFullUrl(rid);
  vspDownload(url);

  setTimeout(()=>{ t.__busy=false; t.disabled=false; }, 1200);
}, true);

// Start observer when /runs page loaded
setTimeout(vspAuditPackInitObserver, 80);
""").strip("\n")

s = s[:m.end()] + "\n" + helpers + "\n" + s[m.end():]
p.write_text(s, encoding="utf-8")
print("[OK] appended v2 hard-inject audit pack logic")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Reload /runs (Ctrl+F5). You should always see Audit Lite / Audit Full per row."
