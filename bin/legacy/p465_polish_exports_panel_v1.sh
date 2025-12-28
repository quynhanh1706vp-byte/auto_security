#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p465_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P465_EXPORTS_PANEL_POLISH_V1"
if MARK in s:
    print("[OK] already patched P465")
    raise SystemExit(0)

# We will append a small override that upgrades the existing P464b panel if present.
# It finds the panel box and adds extra fields + auto-refresh on RID change.
addon = r'''
/* --- VSP_P465_EXPORTS_PANEL_POLISH_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }

  function getRid(){
    try{
      const a = qs('[data-vsp-rid].selected') || qs('[data-rid].selected') || qs('[data-vsp-rid]') || qs('[data-rid]');
      if (a) return (a.getAttribute('data-vsp-rid') || a.getAttribute('data-rid') || '').trim();
      const sel = qs('select[name="rid"]') || qs('select#rid') || qs('select.vsp-rid');
      if (sel && sel.value) return String(sel.value).trim();
      const u = new URL(location.href);
      return (u.searchParams.get('rid')||'').trim();
    }catch(e){ return ""; }
  }

  function buildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set('rid', rid);
    return u.toString();
  }

  function copy(text){
    try{ navigator.clipboard.writeText(String(text||'')); }catch(e){}
  }

  async function fetchSha(rid){
    const r = await fetch(buildUrl('/api/vsp/sha256', rid), {credentials:'same-origin'});
    const j = await r.json().catch(()=>null);
    if(!r.ok) throw new Error('HTTP '+r.status);
    return j || {};
  }

  function ensureExtraUI(box){
    if (qs('.vsp-p465-extra', box)) return;

    const st = document.createElement('style');
    st.textContent = `
      .vsp-p465-extra { margin-top: 10px; border-top: 1px dashed rgba(255,255,255,.10); padding-top: 10px; }
      .vsp-p465-grid { display:grid; grid-template-columns: 120px 1fr; gap:6px 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size: 12px; }
      .vsp-p465-k { opacity:.75; }
      .vsp-p465-v { overflow-wrap:anywhere; }
      .vsp-p465-actions { margin-top: 8px; display:flex; flex-wrap:wrap; gap:10px; }
      .vsp-p465-btn { padding:6px 9px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; cursor:pointer; }
      .vsp-p465-btn:hover { border-color: rgba(255,255,255,.22); }
      .vsp-p465-pill { display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); }
    `;
    if (!qs('#vsp_p465_css')){ st.id='vsp_p465_css'; document.head.appendChild(st); }

    const extra = document.createElement('div');
    extra.className='vsp-p465-extra';
    extra.innerHTML = `
      <div class="vsp-p465-grid">
        <div class="vsp-p465-k">RID</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_rid">-</span></div>
        <div class="vsp-p465-k">File</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_file">-</span></div>
        <div class="vsp-p465-k">Bytes</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_bytes">-</span></div>
        <div class="vsp-p465-k">SHA256</div><div class="vsp-p465-v"><span class="vsp-p465-pill" id="vsp_p465_sha">-</span></div>
      </div>
      <div class="vsp-p465-actions">
        <button class="vsp-p465-btn" id="vsp_p465_copy_rid">Copy RID</button>
        <button class="vsp-p465-btn" id="vsp_p465_copy_sha">Copy SHA</button>
        <button class="vsp-p465-btn" id="vsp_p465_open_exports">Open Exports</button>
      </div>
    `;
    box.appendChild(extra);

    qs('#vsp_p465_copy_rid', extra).addEventListener('click', ()=>copy(qs('#vsp_p465_rid', extra).textContent));
    qs('#vsp_p465_copy_sha', extra).addEventListener('click', ()=>copy(qs('#vsp_p465_sha', extra).textContent));
    qs('#vsp_p465_open_exports', extra).addEventListener('click', ()=>{
      window.open('/api/vsp/exports_v1', '_blank');
    });
  }

  async function refresh(box){
    ensureExtraUI(box);

    const rid = getRid();
    const elRid = qs('#vsp_p465_rid', box);
    const elFile = qs('#vsp_p465_file', box);
    const elBytes = qs('#vsp_p465_bytes', box);
    const elSha = qs('#vsp_p465_sha', box);

    try{
      const j = await fetchSha(rid);
      elRid.textContent = j.rid || rid || '(auto latest)';
      elFile.textContent = j.file || '-';
      elBytes.textContent = (j.bytes!=null ? String(j.bytes) : '-');
      elSha.textContent = j.sha256 || '-';
    }catch(e){
      // keep old values, but show rid at least
      elRid.textContent = rid || '(auto latest)';
    }
  }

  function hook(){
    const box = qs('.vsp-p464b-exports') || qs('.vsp-p464-exports');
    if(!box) return;
    refresh(box);
  }

  // initial + poll when RID changes
  let lastRid = null;
  setInterval(function(){
    const rid = getRid() || '';
    if (rid !== lastRid){
      lastRid = rid;
      hook();
    }
  }, 900);

  setTimeout(hook, 120);
})();
/* --- /VSP_P465_EXPORTS_PANEL_POLISH_V1 --- */
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P465 polish addon")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P465 done. Open /runs and you should see extra fields (RID/File/Bytes/SHA) + buttons." | tee -a "$OUT/log.txt"
