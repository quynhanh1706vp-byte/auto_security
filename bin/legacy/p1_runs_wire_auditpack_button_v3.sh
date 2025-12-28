#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
MARK="VSP_P1_RUNS_WIRE_AUDITPACK_BTN_V3"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditwire_${TS}"
echo "[BACKUP] ${JS}.bak_auditwire_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RUNS_WIRE_AUDITPACK_BTN_V3" in s:
    print("[SKIP] already wired")
    raise SystemExit(0)

# Insert wiring block near end (safe even if other handlers exist)
block = textwrap.dedent(r"""
/* ===================== VSP_P1_RUNS_WIRE_AUDITPACK_BTN_V3 =====================
   Wire existing "Audit Pack" button to audit_pack_download endpoint.
   - default: Lite pack (lite=1)
   - Shift/Alt: Full pack
   - robust RID resolution
============================================================================= */
(function(){
  if (window.__vsp_audit_wire_v3) return;
  window.__vsp_audit_wire_v3 = true;

  function vspToastV3(msg){
    try{
      let t=document.getElementById('vsp_toast_v3');
      if(!t){
        t=document.createElement('div');
        t.id='vsp_toast_v3';
        t.style.cssText='position:fixed;right:16px;bottom:16px;z-index:99999;padding:10px 12px;border-radius:10px;background:#0b1220;color:#cfe3ff;border:1px solid rgba(120,160,255,.25);box-shadow:0 10px 30px rgba(0,0,0,.45);font:13px/1.3 system-ui;opacity:.0;transition:opacity .15s ease';
        document.body.appendChild(t);
      }
      t.textContent=msg;
      t.style.opacity='1';
      clearTimeout(t.__tm);
      t.__tm=setTimeout(()=>{t.style.opacity='0';}, 1400);
    }catch(e){}
  }

  function vspDownloadV3(url){
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

  function auditLiteUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}&lite=1`; }
  function auditFullUrl(rid){ return `/api/vsp/audit_pack_download?rid=${encodeURIComponent(rid)}`; }

  function resolveRid(node){
    if(!node) return '';
    // direct attrs
    let el = node.closest && (node.closest('[data-rid]') || node.closest('[data-run-id]'));
    if(el && el.getAttribute){
      const r = el.getAttribute('data-rid') || el.getAttribute('data-run-id');
      if(r) return r;
    }
    // scan up a bit
    let p=node;
    for(let i=0;i<6 && p; i++){
      if(p.getAttribute){
        const r = p.getAttribute('data-rid') || p.getAttribute('data-run-id');
        if(r) return r;
      }
      p = p.parentElement;
    }
    // fallback: try find RID text in same row first cell
    try{
      const tr = node.closest && node.closest('tr');
      if(tr){
        const a = tr.querySelector('a,button,span,div');
        // but safer: look for something like VSP_ or RUN_
        const txt = tr.innerText || '';
        const m = txt.match(/\b([A-Za-z]+_[A-Za-z0-9]+_[0-9]{8}_[0-9]{6,})\b/);
        if(m && m[1]) return m[1];
      }
    }catch(e){}
    return '';
  }

  function isAuditBtn(t){
    if(!t || !t.getAttribute) return false;
    const act = (t.getAttribute('data-act')||'').toLowerCase();
    if(act === 'audit_pack' || act === 'audit_lite' || act === 'audit_full') return true;
    const tx = (t.textContent||'').trim().toLowerCase();
    return tx === 'audit pack' || tx === 'audit' || tx === 'auditpack';
  }

  document.addEventListener('click', (ev)=>{
    const t = ev.target;
    if(!t) return;
    const btn = (t.closest && t.closest('button')) || t;
    if(!isAuditBtn(btn)) return;

    const rid = btn.getAttribute('data-rid') || resolveRid(btn);
    if(!rid){
      vspToastV3('AuditPack: missing RID');
      return;
    }
    ev.preventDefault();
    ev.stopPropagation();

    const full = !!(ev.shiftKey || ev.altKey);
    const url = full ? auditFullUrl(rid) : auditLiteUrl(rid);

    // UX
    vspToastV3(full ? 'Downloading Audit Pack (FULL)…' : 'Downloading Audit Pack (LITE)…');
    vspDownloadV3(url);
  }, true);

  // Optional: rename visible label to hint shortcut
  try{
    const all = Array.from(document.querySelectorAll('button'));
    all.forEach(b=>{
      const tx=(b.textContent||'').trim().toLowerCase();
      if(tx==='audit pack'){
        b.title = 'Click: Lite pack | Shift/Alt+Click: Full pack';
      }
    });
  }catch(e){}

  console.log('[VSP][Runs] AuditPack wire v3 installed');
})();
""").strip("\n")

s = s + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended audit pack wire v3")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Reload /runs. Click 'Audit Pack' (Lite). Shift+Click for Full."
