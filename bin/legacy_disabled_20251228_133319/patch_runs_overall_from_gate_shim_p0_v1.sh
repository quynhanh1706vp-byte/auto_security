#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_runs_overall_from_gate_shim_p0_v1.js"
TPL="templates/vsp_dashboard_2025.html"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$JSF" ] && cp -f "$JSF" "$JSF.bak_${TS}" && echo "[BACKUP] $JSF.bak_${TS}"
cp -f "$TPL" "$TPL.bak_runs_overall_shim_${TS}" && echo "[BACKUP] $TPL.bak_runs_overall_shim_${TS}"

cat > "$JSF" <<'JS'
/* VSP_RUNS_OVERALL_FROM_GATE_SHIM_P0_V1
 * Goal: replace "N/A" overall in Runs table using canonical gate summary endpoint.
 * Works even if runs panel JS is bundled/unknown.
 */
(function(){
  'use strict';
  if (window.__VSP_RUNS_OVERALL_SHIM_P0_V1) return;
  window.__VSP_RUNS_OVERALL_SHIM_P0_V1 = true;

  const TAG = 'VSP_RUNS_OVERALL_SHIM_P0_V1';
  const RID_RE = /\bVSP_[A-Z0-9]+_\d{8}_\d{6}\b/;
  const CACHE = new Map(); // rid -> overall

  function esc(s){
    return String(s ?? '')
      .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
      .replaceAll('"','&quot;').replaceAll("'","&#039;");
  }

  function ensureStyle(){
    if (document.getElementById('vsp-runs-overall-shim-style')) return;
    const st = document.createElement('style');
    st.id = 'vsp-runs-overall-shim-style';
    st.textContent = `
      .vsp-ov-bdg{display:inline-flex;align-items:center;justify-content:center;
        padding:4px 10px;border-radius:999px;font-size:12px;font-weight:900;
        border:1px solid rgba(255,255,255,.14);letter-spacing:.2px}
      .vsp-ov-green{background:rgba(0,255,140,.12)}
      .vsp-ov-amber{background:rgba(255,190,0,.14)}
      .vsp-ov-red{background:rgba(255,70,70,.14)}
      .vsp-ov-na{background:rgba(160,160,160,.14)}
    `;
    document.head.appendChild(st);
  }

  async function fetchGateOverall(rid){
    if (!rid) return '';
    if (CACHE.has(rid)) return CACHE.get(rid) || '';
    try{
      const r = await fetch(`/api/vsp/run_gate_summary_v1/${encodeURIComponent(rid)}`, { credentials:'same-origin' });
      const j = await r.json().catch(()=>null);
      const ov = (j && (j.overall || (j.overall && j.overall.status))) ? String(j.overall || j.overall.status).toUpperCase() : '';
      CACHE.set(rid, ov);
      return ov;
    }catch(e){
      CACHE.set(rid, '');
      return '';
    }
  }

  function verdictClass(ov){
    const v = String(ov||'').toUpperCase();
    if (v === 'GREEN' || v === 'OK') return 'vsp-ov-green';
    if (v === 'AMBER' || v === 'DEGRADED') return 'vsp-ov-amber';
    if (v === 'RED' || v === 'FAIL') return 'vsp-ov-red';
    return 'vsp-ov-na';
  }

  function findRunsRoot(){
    // from your console log: mounted into #vsp-runs-main
    return document.querySelector('#vsp-runs-main')
      || document.querySelector('[data-vsp-runs]')
      || document.querySelector('#runs_panel')
      || document.body;
  }

  function findRowRid(el){
    if (!el) return '';
    // walk up a bit and search text for RID
    let cur = el;
    for (let i=0;i<6 && cur;i++){
      const txt = (cur.innerText || '').match(RID_RE);
      if (txt && txt[0]) return txt[0];
      cur = cur.parentElement;
    }
    return '';
  }

  async function patchOnce(){
    ensureStyle();
    const root = findRunsRoot();
    if (!root) return;

    // Find "N/A" chips inside runs area
    const nodes = Array.from(root.querySelectorAll('*'))
      .filter(n => n && n.childElementCount === 0)
      .filter(n => (n.textContent || '').trim() === 'N/A');

    if (!nodes.length) return;

    let changed = 0;
    for (const n of nodes){
      // only patch visible ones
      const rid = findRowRid(n);
      if (!rid) continue;

      const ov = await fetchGateOverall(rid);
      const v = ov || 'N/A';

      n.classList.add('vsp-ov-bdg');
      n.classList.remove('vsp-ov-green','vsp-ov-amber','vsp-ov-red','vsp-ov-na');
      n.classList.add(verdictClass(v));

      // keep same width-ish but show real verdict
      n.textContent = (v === 'OK' ? 'GREEN' : v);
      n.title = `RID=${rid}`;
      changed += 1;
    }

    if (changed) console.log(`[${TAG}] patched overall badges:`, changed);
  }

  function boot(){
    let ticks = 0;
    const iv = setInterval(async () => {
      ticks += 1;
      await patchOnce();
      // stop after ~12s (commercial: no infinite polling)
      if (ticks >= 24) clearInterval(iv);
    }, 500);
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', boot, { once:true });
  } else {
    boot();
  }
})();
JS

python3 - <<PY
from pathlib import Path
import re, datetime
tpl = Path("$TPL")
t = tpl.read_text(encoding="utf-8", errors="ignore")

if "vsp_runs_overall_from_gate_shim_p0_v1.js" in t:
    print("[OK] shim already included in template")
    raise SystemExit(0)

stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
tag = f'<script src="/static/js/vsp_runs_overall_from_gate_shim_p0_v1.js?v={stamp}" defer></script>'

# Insert before </body> if possible, else append
if "</body>" in t:
    t2 = re.sub(r"</body>", tag + "\n</body>", t, count=1, flags=re.I)
else:
    t2 = t.rstrip() + "\n" + tag + "\n"
tpl.write_text(t2, encoding="utf-8")
print("[OK] injected shim script tag into template")
PY

node --check "$JSF" >/dev/null && echo "[OK] node --check shim"
echo "[OK] patched runs overall shim => $JSF"
echo "[NEXT] restart UI + hard refresh (Ctrl+Shift+R)"
