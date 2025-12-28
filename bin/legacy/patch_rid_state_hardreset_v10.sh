#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== RID_STATE HARDRESET V10 =="
echo "[TS] $TS"

# --- 1) overwrite rid_state JS (clean + stable contract) ---
F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] && cp -f "$F" "$F.bak_v10_${TS}" && echo "[BACKUP] $F.bak_v10_${TS}"

cat > "$F" <<'JS'
/* VSP_RID_STATE_V10 (commercial stable) */
(function(){
  'use strict';

  const LOGP = '[VSP_RID_STATE_V10]';
  const LS_SELECTED = 'vsp_rid_selected_v1';
  const LS_LATEST   = 'vsp_rid_latest_v1';
  const RID_KEYS_QS = ['rid','run_id','runid'];

  function safeLSGet(k){
    try { return localStorage.getItem(k); } catch(e){ return null; }
  }
  function safeLSSet(k,v){
    try { localStorage.setItem(k, v); } catch(e){}
  }

  function qsRid(){
    try{
      const u = new URL(window.location.href);
      for(const k of RID_KEYS_QS){
        const v = u.searchParams.get(k);
        if(v && String(v).trim()) return String(v).trim();
      }
    }catch(e){}
    return null;
  }

  function getRid(){
    return qsRid() || safeLSGet(LS_SELECTED) || safeLSGet(LS_LATEST) || null;
  }

  function updateBadge(rid){
    const txt = `RID: ${rid || '(none)'}`;

    // common ids
    const ids = ['vsp-rid-badge','rid-badge','vsp_rid_badge','vspRidBadge'];
    for(const id of ids){
      const el = document.getElementById(id);
      if(el){ el.textContent = txt; return; }
    }

    // common classes / data attributes
    const el2 = document.querySelector('[data-vsp-rid-badge], .vsp-rid-badge, .rid-badge');
    if(el2){ el2.textContent = txt; return; }

    // fallback: any small element whose text starts with "RID:"
    const all = document.querySelectorAll('body *');
    for(const el of all){
      const t = (el.textContent || '').trim();
      if(t.startsWith('RID:') && t.length < 80){
        el.textContent = txt;
        return;
      }
    }
  }

  function setRid(rid, why){
    const v = (rid && String(rid).trim()) ? String(rid).trim() : null;
    if(!v) return null;
    safeLSSet(LS_SELECTED, v);
    safeLSSet(LS_LATEST, v);
    updateBadge(v);

    try{
      window.dispatchEvent(new CustomEvent('VSP_RID_CHANGED', { detail: { rid: v, why: why || 'set' } }));
    }catch(e){}
    return v;
  }

  async function pickLatestFromRunsIndex(){
    const url = '/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1';
    const r = await fetch(url, { cache: 'no-store' });
    if(!r.ok) throw new Error('runs_index not ok: ' + r.status);
    const j = await r.json();
    const it = (j && j.items && j.items[0]) ? j.items[0] : null;
    const rid = it && (it.run_id || it.rid || it.id);
    if(rid && String(rid).trim()) return String(rid).trim();
    return null;
  }

  async function pickLatest(){
    // 1) optional override: MUST return string RID or null
    try{
      const ov = window.VSP_RID_PICKLATEST_OVERRIDE_V1;
      if(typeof ov === 'function'){
        const v = await ov();
        if(typeof v === 'string' && v.trim()){
          console.log(LOGP, 'picked by override');
          return setRid(v.trim(), 'override');
        }
      }
    }catch(e){
      console.warn(LOGP, 'override failed', e);
    }

    // 2) default: runs_index
    try{
      const rid = await pickLatestFromRunsIndex();
      if(rid){
        console.log(LOGP, 'picked by runs_index', rid);
        return setRid(rid, 'runs_index');
      }
    }catch(e){
      console.warn(LOGP, 'runs_index pickLatest failed', e);
    }

    return null;
  }

  async function ensure(){
    const cur = getRid();
    updateBadge(cur);
    if(cur) return cur;
    return await pickLatest();
  }

  // compatibility exports
  window.VSP_RID_GET = getRid;
  window.VSP_RID_SET = (rid)=>setRid(rid,'manual');
  window.VSP_RID_PICKLATEST = pickLatest;

  document.addEventListener('DOMContentLoaded', ()=>{ ensure(); });
  console.log(LOGP, 'installed');
})();
JS

node --check "$F" >/dev/null && echo "[OK] rid_state v10 JS syntax OK"

# --- 2) fix templates: remove any <script src="Pxxxxxx_xxxxxx"> + ensure single rid_state tag ---
fix_tpl () {
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_rid_v10_${TS}" && echo "[BACKUP] $T.bak_rid_v10_${TS}"
  TS_ENV="$TS" T_ENV="$T" python3 - <<'PY'
import os, re
from pathlib import Path

ts=os.environ["TS_ENV"]
t=os.environ["T_ENV"]
p=Path(t)
s=p.read_text(encoding="utf-8", errors="replace")

# remove bad Pxxxx script tags (with/without leading slash)
s=re.sub(r'\s*<script[^>]+src=["\']/?P\d{6}_\d{6}["\'][^>]*>\s*</script>\s*', "\n", s, flags=re.I)

# remove any existing rid_state tags
s=re.sub(r'\s*<script[^>]+vsp_rid_state_v1\.js[^>]*>\s*</script>\s*', "\n", s, flags=re.I)

rid_tag=f'<script src="/static/js/vsp_rid_state_v1.js?v={ts}" defer></script>\n'

# insert rid_tag before router script if present
m=re.search(r'(<script[^>]+vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>)', s, flags=re.I)
if m:
  s = s[:m.start()] + rid_tag + s[m.start():]
else:
  # fallback: before </body>
  s = re.sub(r'</body>', rid_tag + '</body>', s, count=1, flags=re.I)

p.write_text(s, encoding="utf-8")
print("[OK] template fixed:", t)
PY
}

fix_tpl "templates/vsp_4tabs_commercial_v1.html"
fix_tpl "templates/vsp_dashboard_2025.html"

echo "== DONE V10 =="
echo "[NEXT] restart 8910 + hard refresh Ctrl+Shift+R"
