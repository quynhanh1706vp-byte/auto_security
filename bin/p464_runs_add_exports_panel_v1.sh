#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need node; need python3; need date; need grep; need sed; need ls; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
warn(){ echo "[WARN] $*" | tee -a "$OUT/log.txt"; }

# pick runs js
CAND=""
if [ -f static/js/vsp_runs_tab_resolved_v1.js ]; then
  CAND="static/js/vsp_runs_tab_resolved_v1.js"
else
  CAND="$(ls -1 static/js/vsp_runs* 2>/dev/null | head -n1 || true)"
fi

if [ -z "$CAND" ] || [ ! -f "$CAND" ]; then
  echo "[ERR] cannot find runs JS (static/js/vsp_runs*). List:" | tee -a "$OUT/log.txt"
  ls -1 static/js | tee -a "$OUT/log.txt" || true
  exit 2
fi

F="$CAND"
cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
ok "backup => $OUT/$(basename "$F").bak_${TS}"
ok "target JS => $F"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P464_RUNS_EXPORTS_PANEL_V1"
if MARK in s:
    print("[OK] already patched P464")
    sys.exit(0)

# Heuristic: inject helper + panel render after DOM is ready or after main render function.
# We'll append a self-contained module and hook into existing container if found.

addon = r'''
/* --- VSP_P464_RUNS_EXPORTS_PANEL_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function vspHtmlEscape(x){
    return String(x).replace(/[&<>"']/g, function(c){
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]||c);
    });
  }

  function vspGetRidBestEffort(){
    // try common places in runs UI
    const a = qs('[data-vsp-rid].selected') || qs('[data-rid].selected') || qs('[data-vsp-rid]') || qs('[data-rid]');
    if (a){
      return (a.getAttribute('data-vsp-rid') || a.getAttribute('data-rid') || '').trim();
    }
    // try select/dropdown
    const sel = qs('select[name="rid"]') || qs('select#rid') || qs('select.vsp-rid');
    if (sel && sel.value) return String(sel.value).trim();
    // try URL param
    try{
      const u = new URL(location.href);
      const rid = (u.searchParams.get('rid')||'').trim();
      if (rid) return rid;
    }catch(e){}
    return "";
  }

  function vspBuildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set('rid', rid);
    return u.toString();
  }

  function vspBtn(text, cls){
    const b = document.createElement('button');
    b.type='button';
    b.className = cls || 'vsp-btn';
    b.textContent = text;
    return b;
  }

  function vspEnsureStyles(){
    if (qs('#vsp_p464_exports_css')) return;
    const st = document.createElement('style');
    st.id='vsp_p464_exports_css';
    st.textContent = `
      .vsp-p464-exports { margin-top: 12px; border: 1px solid rgba(255,255,255,.08); border-radius: 12px; padding: 12px; background: rgba(255,255,255,.03); }
      .vsp-p464-exports h3 { margin: 0 0 8px 0; font-size: 14px; opacity: .9; }
      .vsp-p464-row { display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p464-row .vsp-btn { padding: 8px 10px; border-radius: 10px; border: 1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color: #fff; cursor:pointer; }
      .vsp-p464-row .vsp-btn:hover { border-color: rgba(255,255,255,.22); }
      .vsp-p464-kv { margin-top: 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size: 12px; opacity: .92; }
      .vsp-p464-kv .line { margin: 4px 0; }
      .vsp-p464-pill { display:inline-block; padding:2px 8px; border-radius: 999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); }
      .vsp-p464-muted { opacity:.75; }
      .vsp-p464-err { color: #ff8f8f; }
      .vsp-p464-ok  { color: #b6fcb6; }
    `;
    document.head.appendChild(st);
  }

  async function vspFetchSha256(rid){
    const url = vspBuildUrl('/api/vsp/sha256', rid);
    const r = await fetch(url, {credentials:'same-origin'});
    const j = await r.json().catch(()=>null);
    if (!r.ok) throw new Error((j && (j.err||j.error)) || ('HTTP '+r.status));
    return j;
  }

  function vspCopy(text){
    try{
      navigator.clipboard.writeText(String(text||''));
    }catch(e){}
  }

  function vspRenderExportsPanel(root){
    vspEnsureStyles();
    if (!root) return;

    // avoid duplicates
    if (qs('.vsp-p464-exports', root)) return;

    const box = document.createElement('div');
    box.className = 'vsp-p464-exports';

    const title = document.createElement('h3');
    title.textContent = 'Exports';
    box.appendChild(title);

    const row = document.createElement('div');
    row.className = 'vsp-p464-row';

    const bCsv = vspBtn('Download CSV', 'vsp-btn');
    const bTgz = vspBtn('Download TGZ', 'vsp-btn');
    const bSha = vspBtn('Refresh SHA256', 'vsp-btn');
    row.appendChild(bCsv); row.appendChild(bTgz); row.appendChild(bSha);

    const kv = document.createElement('div');
    kv.className = 'vsp-p464-kv';
    kv.innerHTML = '<div class="line vsp-p464-muted">RID: <span class="vsp-p464-pill" id="vsp_p464_rid">(auto latest)</span></div>'
                 + '<div class="line vsp-p464-muted">SHA256: <span class="vsp-p464-pill" id="vsp_p464_sha">-</span> <button class="vsp-btn" id="vsp_p464_copy_sha" style="padding:6px 8px">Copy</button></div>'
                 + '<div class="line vsp-p464-muted">Bytes: <span class="vsp-p464-pill" id="vsp_p464_bytes">-</span></div>'
                 + '<div class="line vsp-p464-muted">Status: <span class="vsp-p464-pill" id="vsp_p464_status">idle</span></div>';

    box.appendChild(row);
    box.appendChild(kv);
    root.appendChild(box);

    const elRid = qs('#vsp_p464_rid', box);
    const elSha = qs('#vsp_p464_sha', box);
    const elBytes = qs('#vsp_p464_bytes', box);
    const elStatus = qs('#vsp_p464_status', box);
    const bCopy = qs('#vsp_p464_copy_sha', box);

    function setStatus(t, ok){
      elStatus.textContent = t;
      elStatus.classList.remove('vsp-p464-err','vsp-p464-ok');
      if (ok === true) elStatus.classList.add('vsp-p464-ok');
      if (ok === false) elStatus.classList.add('vsp-p464-err');
    }

    async function refresh(){
      const rid = vspGetRidBestEffort();
      elRid.textContent = rid || '(auto latest)';
      setStatus('loading...', null);
      try{
        const j = await vspFetchSha256(rid);
        elRid.textContent = j.rid || rid || '(auto latest)';
        elSha.textContent = j.sha256 || '-';
        elBytes.textContent = (j.bytes!=null ? String(j.bytes) : '-');
        setStatus('ok', true);
      }catch(e){
        setStatus('error: ' + (e && e.message ? e.message : String(e)), false);
      }
    }

    bSha.addEventListener('click', refresh);
    bCopy.addEventListener('click', ()=>vspCopy(elSha.textContent));

    bCsv.addEventListener('click', ()=>{
      const rid = vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_csv', rid), '_blank');
    });
    bTgz.addEventListener('click', ()=>{
      const rid = vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_tgz', rid), '_blank');
    });

    // auto refresh once
    setTimeout(refresh, 50);
  }

  function vspTryHook(){
    // common containers in runs page
    const root =
      qs('#vsp_runs_root') ||
      qs('#vsp_runs') ||
      qs('#runs_root') ||
      qs('.vsp-runs-root') ||
      qs('main') ||
      qs('body');

    if (root) vspRenderExportsPanel(root);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', vspTryHook);
  } else {
    vspTryHook();
  }

  // also re-hook after SPA-like rerenders
  setInterval(vspTryHook, 1200);
})();
 /* --- /VSP_P464_RUNS_EXPORTS_PANEL_V1 --- */
'''

# Append at end (safest)
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended exports panel addon")
PY "$F"

ok "patched $F"

# restart service (optional)
if command -v systemctl >/dev/null 2>&1; then
  ok "restart (optional) ${SVC}"
  sudo systemctl restart "${SVC}" || true
  sudo systemctl is-active "${SVC}" || true
fi

ok "P464 done. Open /runs and you should see Exports panel."
