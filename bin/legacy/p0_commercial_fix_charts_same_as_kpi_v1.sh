#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P0_COMMERCIAL_CHARTS_SAME_AS_KPI_V1"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_consistency_patch_v1.js"

# pick dashboard template safely
TPL=""
for c in templates/vsp_dashboard_2025.html templates/vsp_dashboard_2024.html templates/vsp_dashboard.html templates/vsp5.html; do
  if [ -f "$c" ]; then TPL="$c"; break; fi
done
[ -n "$TPL" ] || err "cannot find dashboard template (tried templates/vsp_dashboard_2025.html ...)"

ok "template=$TPL"
ok "base=$BASE svc=$SVC"

# backup
cp -f "$TPL" "${TPL}.bak_${TS}"
ok "backup: ${TPL}.bak_${TS}"

mkdir -p "$(dirname "$JS")"

cat > "$JS" <<'JS'
/* VSP_P0_COMMERCIAL_CHARTS_SAME_AS_KPI_V1 */
(function(){
  'use strict';

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function detectRidSelect(){
    // Try common IDs first
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = $(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    // Fallback: any SELECT whose options look like VSP_*
    const sels = $all('select');
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getCurrentRid(){
    const u = new URL(window.location.href);
    const qp = u.searchParams.get('rid');
    if (qp) return qp;
    const sel = detectRidSelect();
    if (sel) return sel.value || (sel.options[sel.selectedIndex] && sel.options[sel.selectedIndex].value) || '';
    return '';
  }

  async function fetchDashKpis(rid){
    const url = `/api/vsp/dash_kpis?rid=${encodeURIComponent(rid)}`;
    const r = await fetch(url, {cache:'no-store'});
    if (!r.ok) throw new Error(`dash_kpis HTTP ${r.status}`);
    return await r.json();
  }

  function ensurePanel(){
    // place under main dashboard container if possible
    const host = $('#vsp-dashboard-main') || $('#main') || $('main') || document.body;

    let panel = $('#vsp-commercial-sev-panel');
    if (panel) return panel;

    panel = document.createElement('section');
    panel.id = 'vsp-commercial-sev-panel';
    panel.style.cssText = [
      'margin:14px 0',
      'padding:14px 16px',
      'border:1px solid rgba(255,255,255,0.10)',
      'border-radius:14px',
      'background:rgba(255,255,255,0.04)'
    ].join(';');

    panel.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <div style="font-weight:800;letter-spacing:0.2px;">Severity Distribution (Commercial — from dash_kpis)</div>
        <div id="vsp-commercial-sev-meta" style="opacity:0.8;font-size:12px;">rid: <span id="vsp-commercial-sev-rid">-</span></div>
      </div>
      <div id="vsp-commercial-sev-body" style="margin-top:10px;">
        <div style="opacity:0.85;font-size:12px;">Loading…</div>
      </div>
    `;
    // Insert near top: after KPI row if exists
    const kpiRow = $('#vsp-kpi-row') || $('.vsp-kpi-row');
    if (kpiRow && kpiRow.parentNode){
      kpiRow.parentNode.insertBefore(panel, kpiRow.nextSibling);
    } else {
      host.insertBefore(panel, host.firstChild);
    }
    return panel;
  }

  function sevOrder(){
    return ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'];
  }

  function renderBars(counts){
    const total = sevOrder().reduce((a,k)=>a + (Number(counts[k]||0)||0), 0) || 0;

    const wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex;flex-direction:column;gap:10px;margin-top:6px;';

    for (const k of sevOrder()){
      const v = Number(counts[k]||0)||0;
      const pct = total ? Math.round((v/total)*1000)/10 : 0; // 0.1%
      const row = document.createElement('div');
      row.style.cssText = 'display:grid;grid-template-columns:110px 1fr 110px;gap:10px;align-items:center;';
      row.innerHTML = `
        <div style="font-weight:700;">${k}</div>
        <div style="height:10px;border-radius:999px;overflow:hidden;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.03);">
          <div style="height:100%;width:${Math.min(100, Math.max(0,pct))}%;background:rgba(255,255,255,0.35);"></div>
        </div>
        <div style="text-align:right;opacity:0.9;font-variant-numeric:tabular-nums;">${v} (${pct}%)</div>
      `;
      wrap.appendChild(row);
    }

    const sum = document.createElement('div');
    sum.style.cssText = 'margin-top:6px;opacity:0.8;font-size:12px;';
    sum.textContent = `Total (sum): ${total}`;
    wrap.appendChild(sum);

    return wrap;
  }

  async function refreshFromRid(rid){
    const panel = ensurePanel();
    const ridEl = $('#vsp-commercial-sev-rid');
    const body = $('#vsp-commercial-sev-body');
    if (ridEl) ridEl.textContent = rid || '-';
    if (!rid){
      if (body) body.innerHTML = '<div style="opacity:0.85;font-size:12px;">No RID selected.</div>';
      return;
    }
    try{
      const j = await fetchDashKpis(rid);
      const counts = (j && j.counts_total) || {};
      // store for other code to use if needed
      window.__VSP_COUNTS_TOTAL_FROM_DASH_KPIS = counts;
      window.__VSP_TOTAL_FINDINGS_FROM_DASH_KPIS = j.total_findings;

      if (body){
        body.innerHTML = '';
        body.appendChild(renderBars(counts));
      }
    }catch(e){
      if (body){
        body.innerHTML = `<div style="opacity:0.85;font-size:12px;">No data for this run (dash_kpis failed).</div>
                          <div style="opacity:0.65;font-size:12px;margin-top:6px;">${String(e && e.message ? e.message : e)}</div>`;
      }
    }
  }

  function hookRidChange(){
    const sel = detectRidSelect();
    if (!sel) return;

    // Avoid double-bind
    if (sel.__vspCommercialBound) return;
    sel.__vspCommercialBound = true;

    sel.addEventListener('change', function(){
      const rid = getCurrentRid();
      refreshFromRid(rid);

      // Also try to nudge existing dashboard to refresh other panels if it exposes a hook
      // (does not break if missing)
      try{
        if (typeof window.__vspDashboardReloadRid === 'function'){
          window.__vspDashboardReloadRid(rid);
        } else if (typeof window.__vspReloadAllPanels === 'function'){
          window.__vspReloadAllPanels(rid);
        }
      }catch(_e){}
    }, {passive:true});
  }

  function boot(){
    hookRidChange();
    refreshFromRid(getCurrentRid());
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
JS

ok "wrote $JS"

# patch template to include JS once
python3 - <<PY
from pathlib import Path
import re, sys

tpl = Path("$TPL")
s = tpl.read_text(encoding="utf-8", errors="ignore")

marker = "$MARK"
if marker in s:
    print("[OK] marker already present in template")
    sys.exit(0)

tag = f'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={int(__import__("time").time())}"></script>'
# insert before </body> if possible, else append
if "</body>" in s:
    s = s.replace("</body>", f"<!-- {marker} -->\n{tag}\n</body>")
else:
    s = s + f"\n<!-- {marker} -->\n{tag}\n"

tpl.write_text(s, encoding="utf-8")
print("[OK] patched template include tag + marker")
PY

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  sleep 0.4
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 25 || true
else
  warn "systemctl not found; please restart service manually"
fi

# verify: HTML includes patch js + dash_kpis reachable
RID="${1:-VSP_CI_20251215_173713}"

echo "== [VERIFY] dashboard html contains patch js =="
curl -fsS "$BASE/vsp5?rid=$RID" | grep -oE "vsp_dashboard_consistency_patch_v1\.js\?v=[0-9]+" | head -n 2 || err "template does not include patch js"

echo "== [VERIFY] dash_kpis =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("total", j.get("total_findings"))
print("counts_total", j.get("counts_total"))
PY

ok "done. Open: $BASE/vsp5?rid=$RID and check panel 'Severity Distribution (Commercial — from dash_kpis)'."
