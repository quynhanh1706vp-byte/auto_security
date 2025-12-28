#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
JSF="static/js/vsp_tools_status_from_gate_p0_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_tools_panel_${TS}" && echo "[BACKUP] $TPL.bak_tools_panel_${TS}"
[ -f "$JSF" ] && cp -f "$JSF" "$JSF.bak_${TS}" && echo "[BACKUP] $JSF.bak_${TS}"

cat > "$JSF" <<'JS'
/* VSP_TOOLS_STATUS_FROM_GATE_P0_V1
 * - Shows 8 tools verdict from canonical gate summary
 * - Deterministic: OK/AMBER/RED/NOT_RUN
 */
(function(){
  'use strict';
  if (window.__VSP_TOOLS_STATUS_FROM_GATE_P0_V1) return;
  window.__VSP_TOOLS_STATUS_FROM_GATE_P0_V1 = true;

  const TAG = "VSP_TOOLS_STATUS_FROM_GATE_P0_V1";
  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function esc(s){
    return String(s ?? '')
      .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
      .replaceAll('"','&quot;').replaceAll("'","&#039;");
  }

  function pickMount(){
    return document.querySelector('#vsp_tools_status_panel')
      || document.querySelector('[data-vsp-tools-panel]')
      || null;
  }

  function ensureStyle(){
    if (document.getElementById('vsp-tools-panel-style-v1')) return;
    const st = document.createElement('style');
    st.id = 'vsp-tools-panel-style-v1';
    st.textContent = `
      .vsp-tools-wrap{border-radius:14px;padding:14px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.03);margin-top:12px}
      .vsp-tools-hd{display:flex;align-items:center;justify-content:space-between;gap:10px}
      .vsp-tools-title{font-weight:900;letter-spacing:.2px}
      .vsp-tools-sub{font-size:12px;opacity:.8;margin-top:6px;display:flex;gap:12px;flex-wrap:wrap}
      .vsp-tools-grid{margin-top:10px;display:grid;grid-template-columns:repeat(4, minmax(0, 1fr));gap:10px}
      @media (max-width: 1100px){ .vsp-tools-grid{grid-template-columns:repeat(2, minmax(0,1fr));} }

      .vsp-tool-pill{display:flex;align-items:center;justify-content:space-between;gap:10px;
        padding:10px 12px;border-radius:12px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.02)}
      .vsp-tool-name{font-weight:900;font-size:12px;letter-spacing:.3px}
      .vsp-tool-bdg{display:inline-flex;align-items:center;justify-content:center;
        padding:4px 10px;border-radius:999px;font-size:12px;font-weight:900;border:1px solid rgba(255,255,255,.14)}
      .vsp-bdg-green{background:rgba(0,255,140,.12)}
      .vsp-bdg-amber{background:rgba(255,190,0,.14)}
      .vsp-bdg-red{background:rgba(255,70,70,.14)}
      .vsp-bdg-na{background:rgba(160,160,160,.14)}
      .vsp-tools-btn{margin-top:10px;display:inline-flex;align-items:center;gap:8px;
        padding:7px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);
        background:rgba(255,255,255,.06);cursor:pointer;font-weight:800;font-size:12px}
      .vsp-tools-btn:hover{background:rgba(255,255,255,.10)}
    `;
    document.head.appendChild(st);
  }

  function mapVerdict(v){
    v = String(v || '').toUpperCase();
    if (v === 'GREEN' || v === 'OK') return {txt:'GREEN', cls:'vsp-bdg-green'};
    if (v === 'AMBER' || v === 'DEGRADED') return {txt:'AMBER', cls:'vsp-bdg-amber'};
    if (v === 'RED' || v === 'FAIL') return {txt:'RED', cls:'vsp-bdg-red'};
    if (!v) return {txt:'NOT_RUN', cls:'vsp-bdg-na'};
    return {txt:v, cls:'vsp-bdg-na'};
  }

  async function fetchJSON(url){
    const r = await fetch(url, { credentials:'same-origin' });
    return await r.json();
  }

  function getRID(){
    try{
      const v = localStorage.getItem('vsp_rid_selected_v2');
      if (v && String(v).trim()) return String(v).trim();
    }catch(_){}
    return '';
  }

  async function resolveRID(){
    const ls = getRID();
    if (ls) return ls;
    try{
      const idx = await fetchJSON('/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1');
      const it = idx && idx.items && idx.items[0] ? idx.items[0] : null;
      const rid = it && (it.run_id || it.rid || it.id) ? String(it.run_id || it.rid || it.id) : '';
      return rid;
    }catch(_){
      return '';
    }
  }

  async function render(){
    ensureStyle();
    const mount = pickMount();
    if (!mount) return;

    mount.innerHTML = `
      <div class="vsp-tools-wrap">
        <div class="vsp-tools-hd">
          <div class="vsp-tools-title">8 Tools Status</div>
          <div id="vspToolsOverall" class="vsp-tool-bdg vsp-bdg-na">LOADING</div>
        </div>
        <div class="vsp-tools-sub">
          <div><span style="opacity:.7">RID:</span> <span id="vspToolsRid">-</span></div>
          <div><span style="opacity:.7">Source:</span> <span id="vspToolsSrc">-</span></div>
        </div>
        <div class="vsp-tools-grid" id="vspToolsGrid"></div>
        <button class="vsp-tools-btn" type="button" id="vspToolsRefreshBtn">Refresh tools</button>
      </div>
    `;

    const rid = await resolveRID();
    mount.querySelector('#vspToolsRid').textContent = rid || '(missing rid)';
    if (!rid){
      mount.querySelector('#vspToolsOverall').textContent = 'DEGRADED';
      mount.querySelector('#vspToolsOverall').className = 'vsp-tool-bdg vsp-bdg-amber';
      mount.querySelector('#vspToolsSrc').textContent = 'resolveRID';
      return;
    }

    try{
      const gs = await fetchJSON(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`);
      const overall = gs && (gs.overall || (gs.overall && gs.overall.status)) ? (gs.overall || gs.overall.status) : '';
      const om = mapVerdict(overall);
      const o = mount.querySelector('#vspToolsOverall');
      o.textContent = om.txt;
      o.className = `vsp-tool-bdg ${om.cls}`;
      mount.querySelector('#vspToolsSrc').textContent = (gs && gs.source) ? String(gs.source) : 'gate_summary';

      const by = (gs && gs.by_tool) ? gs.by_tool : {};
      const grid = mount.querySelector('#vspToolsGrid');
      grid.innerHTML = TOOLS.map(tool => {
        const item = by && by[tool] ? by[tool] : null;
        const vv = item && (item.verdict || item.status) ? (item.verdict || item.status) : '';
        const m = mapVerdict(vv);
        const total = item && typeof item.total === 'number' ? item.total : '';
        const hint = total !== '' ? `total=${total}` : '';
        return `
          <div class="vsp-tool-pill" title="${esc(hint)}">
            <div class="vsp-tool-name">${esc(tool)}</div>
            <div class="vsp-tool-bdg ${m.cls}">${esc(m.txt)}</div>
          </div>
        `;
      }).join('');

      // bind refresh
      const btn = mount.querySelector('#vspToolsRefreshBtn');
      if (btn && !btn.__bound){
        btn.__bound = true;
        btn.addEventListener('click', () => render());
      }

      console.log(`[${TAG}] rendered tools for RID`, rid);
    }catch(e){
      mount.querySelector('#vspToolsOverall').textContent = 'DEGRADED';
      mount.querySelector('#vspToolsOverall').className = 'vsp-tool-bdg vsp-bdg-amber';
      mount.querySelector('#vspToolsSrc').textContent = `error`;
      console.warn(`[${TAG}] failed`, e);
    }
  }

  function boot(){
    render();
    window.addEventListener('vsp:rid_changed', render);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', boot, { once:true });
  } else {
    boot();
  }
})();
JS

python3 - <<'PY'
from pathlib import Path
import re, datetime
tpl = Path("templates/vsp_dashboard_2025.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

# Ensure mount exists (place right after gate mount if possible)
if 'id="vsp_tools_status_panel"' not in t:
    if 'id="vsp_gate_panel"' in t:
        t = re.sub(r'(<div\s+id="vsp_gate_panel"\s*>\s*</div>)',
                   r'\1\n<div id="vsp_tools_status_panel" data-vsp-tools-panel="1"></div>',
                   t, count=1, flags=re.I)
    else:
        # fallback: inject near end
        t = t.replace("</body>", '\n<div id="vsp_tools_status_panel" data-vsp-tools-panel="1"></div>\n</body>')

# Ensure script include
if "vsp_tools_status_from_gate_p0_v1.js" not in t:
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    tag = f'<script src="/static/js/vsp_tools_status_from_gate_p0_v1.js?v={stamp}" defer></script>'
    t = re.sub(r"</body>", tag + "\n</body>", t, count=1, flags=re.I)

tpl.write_text(t, encoding="utf-8")
print("[OK] template injected tools panel + script include")
PY

node --check "$JSF" >/dev/null && echo "[OK] node --check"
echo "[OK] patched tools status panel (P0-4B)"
echo "[NEXT] restart UI + hard refresh"
