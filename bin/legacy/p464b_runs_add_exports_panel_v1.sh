#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need ls; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

# pick runs js
F=""
if [ -f static/js/vsp_runs_tab_resolved_v1.js ]; then
  F="static/js/vsp_runs_tab_resolved_v1.js"
else
  F="$(ls -1 static/js/vsp_runs* 2>/dev/null | head -n1 || true)"
fi
[ -n "$F" ] && [ -f "$F" ] || err "cannot find runs JS (static/js/vsp_runs*)"

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
ok "backup => $OUT/$(basename "$F").bak_${TS}"
ok "target  => $F"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
s = path.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P464B_RUNS_EXPORTS_PANEL_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon = r'''
/* --- VSP_P464B_RUNS_EXPORTS_PANEL_V1 --- */
(function(){
  function qs(sel, root){ return (root||document).querySelector(sel); }

  function vspGetRidBestEffort(){
    const a = qs('[data-vsp-rid].selected') || qs('[data-rid].selected') || qs('[data-vsp-rid]') || qs('[data-rid]');
    if (a){
      return (a.getAttribute('data-vsp-rid') || a.getAttribute('data-rid') || '').trim();
    }
    const sel = qs('select[name="rid"]') || qs('select#rid') || qs('select.vsp-rid');
    if (sel && sel.value) return String(sel.value).trim();
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

  function vspEnsureStyles(){
    if (qs('#vsp_p464b_exports_css')) return;
    const st = document.createElement('style');
    st.id='vsp_p464b_exports_css';
    st.textContent = `
      .vsp-p464b-exports { margin-top: 12px; border: 1px solid rgba(255,255,255,.08); border-radius: 12px; padding: 12px; background: rgba(255,255,255,.03); }
      .vsp-p464b-exports h3 { margin: 0 0 8px 0; font-size: 14px; opacity: .9; }
      .vsp-p464b-row { display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p464b-btn { padding: 8px 10px; border-radius: 10px; border: 1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color: #fff; cursor:pointer; }
      .vsp-p464b-btn:hover { border-color: rgba(255,255,255,.22); }
      .vsp-p464b-kv { margin-top: 10px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; font-size: 12px; opacity: .92; }
      .vsp-p464b-kv .line { margin: 4px 0; }
      .vsp-p464b-pill { display:inline-block; padding:2px 8px; border-radius: 999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); }
      .vsp-p464b-err { color: #ff8f8f; }
      .vsp-p464b-ok  { color: #b6fcb6; }
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
    try{ navigator.clipboard.writeText(String(text||'')); }catch(e){}
  }

  function vspRender(root){
    vspEnsureStyles();
    if (!root) return;
    if (qs('.vsp-p464b-exports', root)) return;

    const box=document.createElement('div');
    box.className='vsp-p464b-exports';
    box.innerHTML = `
      <h3>Exports</h3>
      <div class="vsp-p464b-row">
        <button class="vsp-p464b-btn" id="vsp_p464b_csv">Download CSV</button>
        <button class="vsp-p464b-btn" id="vsp_p464b_tgz">Download TGZ</button>
        <button class="vsp-p464b-btn" id="vsp_p464b_sha_btn">Refresh SHA256</button>
      </div>
      <div class="vsp-p464b-kv">
        <div class="line">RID: <span class="vsp-p464b-pill" id="vsp_p464b_rid">(auto latest)</span></div>
        <div class="line">SHA256: <span class="vsp-p464b-pill" id="vsp_p464b_sha">-</span>
          <button class="vsp-p464b-btn" id="vsp_p464b_copy" style="padding:6px 8px">Copy</button>
        </div>
        <div class="line">Bytes: <span class="vsp-p464b-pill" id="vsp_p464b_bytes">-</span></div>
        <div class="line">Status: <span class="vsp-p464b-pill" id="vsp_p464b_status">idle</span></div>
      </div>
    `;
    root.appendChild(box);

    const elRid=qs('#vsp_p464b_rid', box);
    const elSha=qs('#vsp_p464b_sha', box);
    const elBytes=qs('#vsp_p464b_bytes', box);
    const elStatus=qs('#vsp_p464b_status', box);

    function setStatus(t, ok){
      elStatus.textContent=t;
      elStatus.classList.remove('vsp-p464b-err','vsp-p464b-ok');
      if (ok===true) elStatus.classList.add('vsp-p464b-ok');
      if (ok===false) elStatus.classList.add('vsp-p464b-err');
    }

    async function refresh(){
      const rid=vspGetRidBestEffort();
      elRid.textContent=rid || '(auto latest)';
      setStatus('loading...', null);
      try{
        const j=await vspFetchSha256(rid);
        elRid.textContent=j.rid || rid || '(auto latest)';
        elSha.textContent=j.sha256 || '-';
        elBytes.textContent=(j.bytes!=null ? String(j.bytes) : '-');
        setStatus('ok', true);
      }catch(e){
        setStatus('error: '+(e && e.message ? e.message : String(e)), false);
      }
    }

    qs('#vsp_p464b_sha_btn', box).addEventListener('click', refresh);
    qs('#vsp_p464b_copy', box).addEventListener('click', ()=>vspCopy(elSha.textContent));
    qs('#vsp_p464b_csv', box).addEventListener('click', ()=>{
      const rid=vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_csv', rid), '_blank');
    });
    qs('#vsp_p464b_tgz', box).addEventListener('click', ()=>{
      const rid=vspGetRidBestEffort();
      window.open(vspBuildUrl('/api/vsp/export_tgz', rid), '_blank');
    });

    setTimeout(refresh, 80);
  }

  function hook(){
    const root =
      qs('#vsp_runs_root') ||
      qs('#vsp_runs') ||
      qs('#runs_root') ||
      qs('.vsp-runs-root') ||
      qs('main') ||
      qs('body');
    if (root) vspRender(root);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', hook);
  } else {
    hook();
  }
  setInterval(hook, 1200);
})();
 /* --- /VSP_P464B_RUNS_EXPORTS_PANEL_V1 --- */
'''

path.write_text(s.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended addon")
PY

python3 -m py_compile /dev/null >/dev/null 2>&1 || true
ok "patched $F"

if command -v systemctl >/dev/null 2>&1; then
  ok "restart ${SVC}"
  sudo systemctl restart "${SVC}" || true
  sudo systemctl is-active "${SVC}" || true
fi

ok "DONE. Open /runs (or /c/runs) and look for 'Exports' panel."
