#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_tool_pills_verdict_from_gate_p0_v2.js"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_toolpillv2_${TS}" && echo "[BACKUP] $TPL.bak_toolpillv2_${TS}"
[ -f "$JSF" ] && cp -f "$JSF" "$JSF.bak_${TS}" && echo "[BACKUP] $JSF.bak_${TS}"

cat > "$JSF" <<'JS'
(function(){
  'use strict';
  if (window.__VSP_TOOL_PILLS_VERDICT_P0_V2) return;
  window.__VSP_TOOL_PILLS_VERDICT_P0_V2 = true;

  const TAG='VSP_TOOL_PILLS_VERDICT_P0_V2';
  const TOOLS=["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function ensureStyle(){
    if (document.getElementById('vsp-toolpill-style-v2')) return;
    const st=document.createElement('style');
    st.id='vsp-toolpill-style-v2';
    st.textContent=`
      .vsp-vbdg{display:inline-flex;align-items:center;justify-content:center;
        padding:3px 8px;border-radius:999px;font-size:11px;font-weight:900;
        border:1px solid rgba(255,255,255,.14); margin-left:8px}
      .vsp-vg{background:rgba(0,255,140,.12)}
      .vsp-va{background:rgba(255,190,0,.14)}
      .vsp-vr{background:rgba(255,70,70,.14)}
      .vsp-vn{background:rgba(160,160,160,.14)}
    `;
    document.head.appendChild(st);
  }

  function map(v){
    v=String(v||'').toUpperCase();
    if (v==='OK') v='GREEN';
    if (v==='FAIL') v='RED';
    if (v==='DEGRADED') v='AMBER';
    if (v==='GREEN') return {t:'GREEN', c:'vsp-vbdg vsp-vg'};
    if (v==='AMBER') return {t:'AMBER', c:'vsp-vbdg vsp-va'};
    if (v==='RED') return {t:'RED', c:'vsp-vbdg vsp-vr'};
    return {t:'NOT_RUN', c:'vsp-vbdg vsp-vn'};
  }

  async function resolveRID(){
    try{
      const v=localStorage.getItem('vsp_rid_selected_v2');
      if (v && String(v).trim()) return String(v).trim();
    }catch(_){}
    try{
      const r=await fetch('/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1',{credentials:'same-origin'});
      const j=await r.json();
      return String(j?.items?.[0]?.run_id || '');
    }catch(_){ return ''; }
  }

  async function fetchGate(rid){
    const r=await fetch(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`,{credentials:'same-origin'});
    return await r.json();
  }

  function findToolNodes(tool){
    const nodes=[...document.querySelectorAll('div,span,a,button')];
    const up=tool.toUpperCase();
    return nodes.filter(n=>{
      const tx=(n.innerText||'').trim().toUpperCase();
      return tx===up || tx.startsWith(up+'\n') || tx.startsWith(up+' ') || tx.includes('\n'+up+'\n') || tx.includes(' '+up+'\n');
    });
  }

  function decorate(by){
    let n=0;
    for (const tool of TOOLS){
      const nodes=findToolNodes(tool);
      if (!nodes.length) continue;
      const vv = by?.[tool]?.verdict || by?.[tool]?.status || '';
      const m = map(vv);

      for (const el of nodes){
        if (el.querySelector && el.querySelector('[data-vsp-tool-verdict="1"]')) continue;
        const bdg=document.createElement('span');
        bdg.className=m.c;
        bdg.textContent=m.t;
        bdg.setAttribute('data-vsp-tool-verdict','1');
        el.appendChild(bdg);
        n++;
      }
    }
    if (n) console.log(`[${TAG}] decorated`, n, 'tool nodes');
    return n;
  }

  async function tick(){
    ensureStyle();
    const rid=await resolveRID();
    if (!rid) return 0;
    const gs=await fetchGate(rid).catch(()=>null);
    if (!gs) return 0;
    return decorate(gs.by_tool || {});
  }

  function boot(){
    let tries=0;
    const iv=setInterval(async ()=>{
      tries++;
      const n=await tick();
      if (n>0 && tries>=3) { /* keep a bit to catch rerender */ }
      if (tries>=60) clearInterval(iv); // 30s
    }, 500);
  }

  if (document.readyState==='loading') document.addEventListener('DOMContentLoaded', boot, {once:true});
  else boot();
})();
JS

python3 - <<'PY'
from pathlib import Path
import re, datetime
tpl=Path("templates/vsp_dashboard_2025.html")
t=tpl.read_text(encoding="utf-8", errors="ignore")
if "vsp_tool_pills_verdict_from_gate_p0_v2.js" not in t:
  stamp=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
  tag=f'<script src="/static/js/vsp_tool_pills_verdict_from_gate_p0_v2.js?v={stamp}" defer></script>'
  t=re.sub(r"</body>", tag+"\n</body>", t, count=1, flags=re.I)
tpl.write_text(t, encoding="utf-8")
print("[OK] injected tool pills verdict shim v2")
PY

node --check "$JSF" >/dev/null && echo "[OK] node --check"
echo "[OK] patched tool pills verdict shim v2"
echo "[NEXT] restart UI + hard refresh"
