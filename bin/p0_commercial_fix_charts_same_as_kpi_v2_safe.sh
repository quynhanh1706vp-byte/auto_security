#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P0_COMMERCIAL_CHARTS_SAME_AS_KPI_V2_SAFE"
RID="${1:-VSP_CI_20251215_173713}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

trap 'rc=$?; echo "[ERR] script failed rc=$rc at line=$LINENO cmd=${BASH_COMMAND}" >&2; exit $rc' ERR

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_consistency_patch_v1.js"

# Find a dashboard template more robustly
TPL=""
cands=(
  templates/vsp_dashboard_2025.html
  templates/vsp_dashboard_2024.html
  templates/vsp_dashboard.html
  templates/vsp5.html
)
for c in "${cands[@]}"; do
  [ -f "$c" ] && TPL="$c" && break
done

if [ -z "$TPL" ]; then
  # fallback: any template containing vsp5 or dashboard main marker
  if [ -d templates ]; then
    TPL="$(grep -RIl --include='*.html' -E 'vsp5|vsp-dashboard-main|VSP' templates | head -n 1 || true)"
  fi
fi
[ -n "$TPL" ] || err "cannot find dashboard template under ./templates"

ok "template=$TPL"
ok "BASE=$BASE RID=$RID SVC=$SVC"

cp -f "$TPL" "${TPL}.bak_${TS}"
ok "backup: ${TPL}.bak_${TS}"

mkdir -p "$(dirname "$JS")"

cat > "$JS" <<'JS'
/* VSP_P0_COMMERCIAL_CHARTS_SAME_AS_KPI_V2_SAFE */
(function(){
  'use strict';

  function $(sel, root){ return (root||document).querySelector(sel); }
  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function detectRidSelect(){
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = $(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    const sels = $all('select');
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getRid(){
    const u = new URL(window.location.href);
    const qp = u.searchParams.get('rid');
    if (qp) return qp;
    const sel = detectRidSelect();
    if (sel) return sel.value || '';
    return '';
  }

  async function fetchDashKpis(rid){
    const url = `/api/vsp/dash_kpis?rid=${encodeURIComponent(rid)}`;
    const r = await fetch(url, {cache:'no-store'});
    if (!r.ok) throw new Error(`dash_kpis HTTP ${r.status}`);
    return await r.json();
  }

  function ensurePanel(){
    const host = $('#vsp-dashboard-main') || $('#main') || $('main') || document.body;
    let panel = $('#vsp-commercial-sev-panel');
    if (panel) return panel;

    panel = document.createElement('section');
    panel.id = 'vsp-commercial-sev-panel';
    panel.style.cssText = [
      'margin:14px 0','padding:14px 16px',
      'border:1px solid rgba(255,255,255,0.10)',
      'border-radius:14px','background:rgba(255,255,255,0.04)'
    ].join(';');

    panel.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
        <div style="font-weight:800;letter-spacing:0.2px;">Severity Distribution (Commercial — from dash_kpis)</div>
        <div style="opacity:0.8;font-size:12px;">rid: <span id="vsp-commercial-sev-rid">-</span></div>
      </div>
      <div id="vsp-commercial-sev-body" style="margin-top:10px;">
        <div style="opacity:0.85;font-size:12px;">Loading…</div>
      </div>
    `;

    const kpiRow = $('#vsp-kpi-row') || $('.vsp-kpi-row');
    if (kpiRow && kpiRow.parentNode) kpiRow.parentNode.insertBefore(panel, kpiRow.nextSibling);
    else host.insertBefore(panel, host.firstChild);

    return panel;
  }

  const ORDER = ['CRITICAL','HIGH','MEDIUM','LOW','INFO','TRACE'];

  function render(counts){
    const total = ORDER.reduce((a,k)=>a + (Number(counts[k]||0)||0), 0) || 0;
    const wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex;flex-direction:column;gap:10px;margin-top:6px;';

    for (const k of ORDER){
      const v = Number(counts[k]||0)||0;
      const pct = total ? Math.round((v/total)*1000)/10 : 0;
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

  async function refresh(rid){
    ensurePanel();
    const ridEl = $('#vsp-commercial-sev-rid');
    const body  = $('#vsp-commercial-sev-body');
    if (ridEl) ridEl.textContent = rid || '-';

    if (!rid){
      if (body) body.innerHTML = '<div style="opacity:0.85;font-size:12px;">No RID selected.</div>';
      return;
    }
    try{
      const j = await fetchDashKpis(rid);
      const counts = (j && j.counts_total) || {};
      window.__VSP_COUNTS_TOTAL_FROM_DASH_KPIS = counts;
      if (body){
        body.innerHTML = '';
        body.appendChild(render(counts));
      }
    }catch(e){
      if (body){
        body.innerHTML = `<div style="opacity:0.85;font-size:12px;">No data for this run.</div>
                          <div style="opacity:0.65;font-size:12px;margin-top:6px;">${String(e && e.message ? e.message : e)}</div>`;
      }
    }
  }

  function hook(){
    const sel = detectRidSelect();
    if (sel && !sel.__vspCommercialBound){
      sel.__vspCommercialBound = true;
      sel.addEventListener('change', ()=>refresh(getRid()), {passive:true});
    }
  }

  function boot(){
    hook();
    refresh(getRid());
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
JS

ok "wrote $JS"

python3 - <<PY
from pathlib import Path
import time

tpl = Path("$TPL")
s = tpl.read_text(encoding="utf-8", errors="ignore")
marker = "$MARK"
if marker in s:
    print("[OK] marker already present; skip inject")
else:
    tag = f'<script src="/static/js/vsp_dashboard_consistency_patch_v1.js?v={int(time.time())}"></script>'
    if "</body>" in s:
        s = s.replace("</body>", f"<!-- {marker} -->\n{tag}\n</body>")
    else:
        s = s + f"\n<!-- {marker} -->\n{tag}\n"
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected script tag + marker")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || warn "systemctl restart failed (service may be non-systemd); continue"
  sleep 0.4
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 20 || true
else
  warn "no systemctl; restart service manually if needed"
fi

echo "== [VERIFY soft] try to find injected JS in HTML (no hard fail) =="
found=0
for path in "/vsp5?rid=$RID" "/vsp5" "/" "/dashboard"; do
  if curl -sS "$BASE$path" | grep -q "vsp_dashboard_consistency_patch_v1\.js"; then
    ok "found injected JS in $path"
    found=1
    break
  else
    warn "not found in $path"
  fi
done
[ "$found" -eq 1 ] || warn "injected JS not detected in common pages. Template might not be used by current route."

echo "== [VERIFY soft] dash_kpis =="
if curl -sS "$BASE/api/vsp/dash_kpis?rid=$RID" >/tmp/_dash_kpis.json 2>/dev/null; then
  python3 - <<'PY'
import json
j=json.load(open("/tmp/_dash_kpis.json","r",encoding="utf-8"))
print("total", j.get("total_findings"))
print("counts_total", j.get("counts_total"))
PY
else
  warn "dash_kpis curl failed; check BASE/RID/service"
fi

ok "done. Open: $BASE/vsp5?rid=$RID (look for panel: 'Severity Distribution (Commercial — from dash_kpis)')"
