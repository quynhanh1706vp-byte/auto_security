#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sudo; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

MARK="VSP_P1_STATUSBAR_OK_DEGRADED_V1"
if grep -q "$MARK" "$TPL"; then
  echo "[OK] already patched: $TPL"
  exit 0
fi

cp -f "$TPL" "${TPL}.bak_statusbar_${TS}"
echo "[BACKUP] ${TPL}.bak_statusbar_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="replace")

inject = r"""
<!-- VSP_P1_STATUSBAR_OK_DEGRADED_V1 -->
<style>
#vspStatusBar{ margin:10px 0 14px 0; padding:10px 12px; border-radius:14px;
  border:1px solid rgba(148,163,184,.25); background:rgba(15,23,42,.45); color:#e2e8f0; display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
#vspStatusPill{ padding:4px 10px; border-radius:999px; font-size:12px; border:1px solid rgba(148,163,184,.25); }
.vsp-ok{ border-color:rgba(34,197,94,.35); background:rgba(34,197,94,.12); color:#86efac; }
.vsp-deg{ border-color:rgba(251,191,36,.35); background:rgba(251,191,36,.10); color:#fde68a; }
#vspStatusMeta{ font-size:12px; opacity:.9; }
#vspStatusMeta code{ background:rgba(15,23,42,.55); padding:2px 6px; border-radius:8px; border:1px solid rgba(148,163,184,.25); color:#e2e8f0; }
</style>

<div id="vspStatusBar">
  <span id="vspStatusPill" class="vsp-ok">✅ OK</span>
  <span id="vspStatusMeta">RID: <code id="vspStatusRid">N/A</code> • Degraded: <span id="vspStatusDeg">0</span></span>
</div>

<script>
(function(){
  function scanDegraded(obj, out, path){
    if(!obj || typeof obj !== 'object') return;
    if(obj.degraded === true) out.add(path || 'unknown');
    if(obj.mode && String(obj.mode).toUpperCase().includes('DEGRAD')) out.add(path || 'unknown');
    for(const k of Object.keys(obj)){
      const v=obj[k];
      const p=path ? (path + '.' + k) : k;
      if(v && typeof v === 'object') scanDegraded(v, out, p);
    }
  }
  async function getLatestRid(){
    const r = await fetch('/api/vsp/runs?limit=1', {cache:'no-store'});
    if(!r.ok) return '';
    const j = await r.json().catch(()=>null);
    return (j && j.items && j.items[0] && j.items[0].run_id) ? j.items[0].run_id : '';
  }
  async function getGateSummary(rid){
    const url='/api/vsp/run_file?rid='+encodeURIComponent(rid)+'&name='+encodeURIComponent('reports/run_gate_summary.json');
    const r=await fetch(url,{cache:'no-store'});
    if(!r.ok) return null;
    return await r.json().catch(()=>null);
  }
  async function main(){
    const pill=document.getElementById('vspStatusPill');
    const ridEl=document.getElementById('vspStatusRid');
    const degEl=document.getElementById('vspStatusDeg');
    if(!pill||!ridEl||!degEl) return;

    const rid = await getLatestRid();
    if(!rid) return;
    ridEl.textContent = rid;

    const gs = await getGateSummary(rid);
    if(!gs){ pill.className=''; pill.classList.add('vsp-deg'); pill.textContent='⚠️ DEGRADED'; degEl.textContent='?'; return; }

    const items=new Set();
    scanDegraded(gs, items, '');
    const n = items.size;
    degEl.textContent = String(n);

    if(n>0){
      pill.className='vsp-deg';
      pill.textContent='⚠️ DEGRADED';
    }else{
      pill.className='vsp-ok';
      pill.textContent='✅ OK';
    }
  }
  document.addEventListener('DOMContentLoaded', main);
})();
</script>
<!-- /VSP_P1_STATUSBAR_OK_DEGRADED_V1 -->
"""

# inject right after <body ...>
if "<body" in s and "</body>" in s:
  idx=s.find("<body")
  gt=s.find(">", idx)
  if gt!=-1:
    s=s[:gt+1]+"\n"+inject+"\n"+s[gt+1:]
  else:
    s=inject+"\n"+s
else:
  s += "\n" + inject

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

sudo systemctl restart vsp-ui-8910.service
curl -fsS http://127.0.0.1:8910/vsp5 | grep -q "$MARK" && echo "[OK] /vsp5 statusbar injected"
