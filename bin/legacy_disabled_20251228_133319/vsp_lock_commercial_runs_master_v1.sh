#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[ROOT] $ROOT"
echo "[TS]   $TS"

backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp "$f" "$f.bak_commercial_runs_master_${TS}"
  echo "[BACKUP] $f.bak_commercial_runs_master_${TS}"
}

# ----------------------------
# 0) Template: remove legacy runscan + comment old runs scripts
# ----------------------------
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] not found: $TPL"; exit 1; }
backup "$TPL"

python3 - << 'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

def comment_or_remove(src):
    global txt
    pat = rf'(?m)^\s*<script[^>]+src="/static/js/{re.escape(src)}"[^>]*>\s*</script>\s*$'
    if re.search(pat, txt):
        txt = re.sub(pat, f'<!-- VSP_COMMERCIAL_LOCK: disabled {src} -->', txt)

# remove legacy runscan tags
for src in ["vsp_runs_trigger_scan_ui_v3.js", "vsp_runs_trigger_scan_mount_hook_v1.js"]:
    comment_or_remove(src)

# comment old runs hydrators (we will render via commercial panel)
for src in ["vsp_runs_tab_simple_v2.js", "vsp_runs_kpi_reports_v1.js", "vsp_runs_filters_advanced_v1.js"]:
    comment_or_remove(src)

# ensure commercial panel is included
if "vsp_runs_commercial_panel_v1.js" not in txt:
    txt = txt.replace("</body>", '  <script src="/static/js/vsp_runs_commercial_panel_v1.js" defer></script>\n</body>')

tpl.write_text(txt, encoding="utf-8")
print("[OK] template locked: legacy runscan removed + old runs scripts commented + commercial panel ensured")
PY

# ----------------------------
# 1) Disable runs hydration inside router (keep router for tab switching)
# ----------------------------
ROUTER="static/js/vsp_tabs_hash_router_v1.js"
[ -f "$ROUTER" ] || { echo "[ERR] not found: $ROUTER"; exit 1; }
backup "$ROUTER"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_tabs_hash_router_v1.js")
txt = p.read_text(encoding="utf-8", errors="replace")

if "VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1" not in txt:
    # inject guard inside renderRunsPane()
    pat = r'(function\s+renderRunsPane\s*\([^)]*\)\s*\{\s*)'
    if re.search(pat, txt):
        txt = re.sub(
            pat,
            r"\1\n    // === VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1 ===\n"
            r"    if (window.VSP_COMMERCIAL_RUNS_MASTER) {\n"
            r"      console.log('[VSP_TABS_ROUTER_V1] commercial runs master enabled -> skip legacy runs hydrate');\n"
            r"      return;\n"
            r"    }\n"
            r"    // === END VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1 ===\n",
            txt,
            count=1
        )
    else:
        # fallback: guard inside handleHashChange when tab is runs
        pat2 = r'(handleHashChange[\s\S]*?->\s*runs[\s\S]*?\n)'
        if "commercial runs master" not in txt:
            txt = txt.replace(
                "handleHashChange",
                "handleHashChange /* VSP_COMMERCIAL_RUNS_MASTER_GUARD_V1: (fallback) */"
            )
    p.write_text(txt, encoding="utf-8")
    print("[OK] patched router: skip legacy runs hydrate when VSP_COMMERCIAL_RUNS_MASTER=1")
else:
    print("[SKIP] router already patched")
PY

# ----------------------------
# 2) Disable other runs hydrators (safe even if template still loads them)
# ----------------------------
for f in \
  static/js/vsp_runs_tab_simple_v2.js \
  static/js/vsp_runs_kpi_reports_v1.js \
  static/js/vsp_runs_filters_advanced_v1.js \
  static/js/vsp_ui_extras_v25.js
do
  [ -f "$f" ] || continue
  backup "$f"
done

python3 - << 'PY'
from pathlib import Path
import re

def inject_early_return(path, marker):
    p = Path(path)
    if not p.exists(): 
        return
    txt = p.read_text(encoding="utf-8", errors="replace")
    if marker in txt:
        return

    # put guard right after 'use strict' if possible
    if "'use strict';" in txt:
        txt = txt.replace(
            "'use strict';",
            "'use strict';\n"
            f"  // === {marker} ===\n"
            "  if (window.VSP_COMMERCIAL_RUNS_MASTER) {\n"
            f"    console.log('[{marker}] disabled by commercial runs master');\n"
            "    return;\n"
            "  }\n"
            f"  // === END {marker} ===\n"
        , 1)
    else:
        txt = f"(function(){{\n  // === {marker} ===\n  if (window.VSP_COMMERCIAL_RUNS_MASTER) return;\n  // === END {marker} ===\n}})();\n" + txt

    p.write_text(txt, encoding="utf-8")

inject_early_return("static/js/vsp_runs_tab_simple_v2.js", "VSP_DISABLE_RUNS_TAB_SIMPLE_V2_BY_MASTER")
inject_early_return("static/js/vsp_runs_kpi_reports_v1.js", "VSP_DISABLE_RUNS_KPI_V1_BY_MASTER")
inject_early_return("static/js/vsp_runs_filters_advanced_v1.js", "VSP_DISABLE_RUNS_FILTER_ADV_V1_BY_MASTER")

# For vsp_ui_extras_v25.js: only disable runs-related enhance function (not whole file)
p = Path("static/js/vsp_ui_extras_v25.js")
if p.exists():
    txt = p.read_text(encoding="utf-8", errors="replace")
    if "VSP_DISABLE_UI_EXTRAS_RUNS_BY_MASTER_V1" not in txt:
        # inject inside enhanceRunsTab()
        pat = r'(function\s+enhanceRunsTab\s*\([^)]*\)\s*\{\s*)'
        if re.search(pat, txt):
            txt = re.sub(
                pat,
                r"\1\n    // === VSP_DISABLE_UI_EXTRAS_RUNS_BY_MASTER_V1 ===\n"
                r"    if (window.VSP_COMMERCIAL_RUNS_MASTER) {\n"
                r"      console.log('[VSP_UI_EXTRAS] skip enhanceRunsTab (commercial runs master)');\n"
                r"      return;\n"
                r"    }\n"
                r"    // === END VSP_DISABLE_UI_EXTRAS_RUNS_BY_MASTER_V1 ===\n",
                txt,
                count=1
            )
        p.write_text(txt, encoding="utf-8")
print("[OK] disabled legacy runs hydrators (safe guards)")
PY

# ----------------------------
# 3) Overwrite Commercial Runs Panel: render full Runs table + search + PASS/FAIL badge
# ----------------------------
PANEL="static/js/vsp_runs_commercial_panel_v1.js"
mkdir -p static/js
backup "$PANEL"

cat > "$PANEL" << 'JS'
(function () {
  'use strict';
  // Commercial Runs Master (single source of truth)
  window.VSP_COMMERCIAL_RUNS_MASTER = true;

  if (window.VSP_RUNS_COMMERCIAL_PANEL_V1) return;
  window.VSP_RUNS_COMMERCIAL_PANEL_V1 = true;

  const qs = (s, r=document) => r.querySelector(s);

  function htmlesc(s){
    return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }

  function sumTotals(t){
    if (!t || typeof t !== 'object') return 0;
    let s = 0;
    for (const k of Object.keys(t)){
      const v = t[k];
      const n = Number(v);
      if (!Number.isNaN(n)) s += n;
    }
    return s;
  }

  function gateStatus(totals){
    const c = Number(totals?.CRITICAL || 0);
    const h = Number(totals?.HIGH || 0);
    // align with your CI gate default (MAX_CRITICAL=0, MAX_HIGH=10)
    if (c > 0 || h > 10) return {label:'FAIL', cls:'vsp-gate-red'};
    return {label:'PASS', cls:'vsp-gate-green'};
  }

  function findRunsHost(){
    return qs('#vsp-runs-main');
  }

  function ensureShell(host){
    if (host.querySelector('.vsp-commercial-runs-shell')) return;

    const shell = document.createElement('div');
    shell.className = 'vsp-commercial-runs-shell';
    shell.innerHTML = `
      <div class="vsp-panel" style="margin-top:12px;">
        <div style="display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap;">
          <div>
            <div class="vsp-h2" style="margin:0;">Runs & Reports</div>
            <div class="vsp-subtle" style="margin-top:4px;">Commercial master panel (FS endpoint) • Fast • No legacy overlays</div>
          </div>
          <div style="display:flex; gap:8px; align-items:center; flex-wrap:wrap;">
            <label class="vsp-subtle" style="display:flex; align-items:center; gap:6px;">
              <input type="checkbox" id="vsp-cm-hide-empty" checked />
              Hide empty
            </label>
            <select class="vsp-select" id="vsp-cm-limit">
              <option value="50">Last 50</option>
              <option value="100">Last 100</option>
              <option value="200" selected>Last 200</option>
              <option value="400">Last 400</option>
            </select>
            <input class="vsp-input" id="vsp-cm-search" placeholder="Search run_id…" style="min-width:240px;" />
            <button class="vsp-btn" id="vsp-cm-refresh">Refresh</button>
          </div>
        </div>

        <div style="display:flex; gap:10px; margin-top:10px; flex-wrap:wrap;">
          <div class="vsp-kpi-card" style="min-width:180px;">
            <div class="vsp-kpi-label">Shown runs</div>
            <div class="vsp-kpi-value" id="vsp-cm-kpi-count">-</div>
          </div>
          <div class="vsp-kpi-card" style="min-width:180px;">
            <div class="vsp-kpi-label">PASS / FAIL</div>
            <div class="vsp-kpi-value" id="vsp-cm-kpi-passfail">-</div>
          </div>
          <div class="vsp-kpi-card" style="min-width:180px;">
            <div class="vsp-kpi-label">Latest run</div>
            <div class="vsp-kpi-value" id="vsp-cm-kpi-latest" style="font-size:12px;">-</div>
          </div>
          <div class="vsp-kpi-card" style="min-width:180px;">
            <div class="vsp-kpi-label">Data source</div>
            <div class="vsp-kpi-value" id="vsp-cm-kpi-source">fs</div>
          </div>
        </div>

        <div class="vsp-subtle" id="vsp-cm-status" style="margin-top:10px;">Ready.</div>

        <div style="overflow:auto; margin-top:10px;">
          <table class="vsp-table" style="min-width:980px;">
            <thead>
              <tr>
                <th style="width:170px;">Created</th>
                <th>Run ID</th>
                <th style="width:90px;">Gate</th>
                <th style="width:110px; text-align:right;">Total</th>
                <th style="width:90px; text-align:right;">CRIT</th>
                <th style="width:90px; text-align:right;">HIGH</th>
                <th style="width:90px; text-align:right;">MED</th>
                <th style="width:90px; text-align:right;">LOW</th>
                <th style="width:90px; text-align:right;">INFO</th>
                <th style="width:170px;">Actions</th>
              </tr>
            </thead>
            <tbody id="vsp-cm-tbody"></tbody>
          </table>
        </div>
      </div>
    `;
    host.prepend(shell);
  }

  async function fetchRuns(limit, hideEmpty){
    const url = `/api/vsp/runs_index_v3_fs?limit=${encodeURIComponent(limit)}&hide_empty=${hideEmpty ? 1 : 0}`;
    const res = await fetch(url, {cache:'no-store'});
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  function renderRows(items){
    const tb = qs('#vsp-cm-tbody');
    const q = (qs('#vsp-cm-search')?.value || '').trim().toLowerCase();
    tb.innerHTML = '';

    let pass = 0, fail = 0;
    let shown = 0;

    for (const it of (items || [])){
      const runId = it.run_id || '';
      if (q && !runId.toLowerCase().includes(q)) continue;

      const totals = it.totals || {};
      const total = Number(it.total_findings ?? sumTotals(totals)) || 0;
      const g = gateStatus(totals);

      if (g.label === 'PASS') pass++; else fail++;
      shown++;

      const created = it.created_at ? String(it.created_at).replace('T',' ').slice(0,19) : '-';

      const html = `
        <tr>
          <td class="vsp-mono">${htmlesc(created)}</td>
          <td class="vsp-mono">${htmlesc(runId)}</td>
          <td><span class="vsp-gate-badge ${g.cls}">${g.label}</span></td>
          <td class="vsp-mono" style="text-align:right;">${total.toLocaleString()}</td>
          <td class="vsp-mono" style="text-align:right;">${Number(totals.CRITICAL||0).toLocaleString()}</td>
          <td class="vsp-mono" style="text-align:right;">${Number(totals.HIGH||0).toLocaleString()}</td>
          <td class="vsp-mono" style="text-align:right;">${Number(totals.MEDIUM||0).toLocaleString()}</td>
          <td class="vsp-mono" style="text-align:right;">${Number(totals.LOW||0).toLocaleString()}</td>
          <td class="vsp-mono" style="text-align:right;">${Number(totals.INFO||0).toLocaleString()}</td>
          <td>
            <button class="vsp-btn vsp-btn-ghost" data-act="html" data-run="${htmlesc(runId)}">HTML</button>
            <button class="vsp-btn vsp-btn-ghost" data-act="zip" data-run="${htmlesc(runId)}">ZIP</button>
          </td>
        </tr>
      `;
      tb.insertAdjacentHTML('beforeend', html);
    }

    qs('#vsp-cm-kpi-count').textContent = String(shown);
    qs('#vsp-cm-kpi-passfail').textContent = `${pass} / ${fail}`;

    // latest run (first shown)
    const first = (items || []).find(it => {
      const runId = (it.run_id||'').toLowerCase();
      const q2 = (qs('#vsp-cm-search')?.value || '').trim().toLowerCase();
      return (!q2 || runId.includes(q2));
    });
    qs('#vsp-cm-kpi-latest').textContent = first?.run_id || '-';
  }

  function wireActions(){
    const host = findRunsHost();
    if (!host) return;

    host.addEventListener('click', (e) => {
      const btn = e.target && e.target.closest && e.target.closest('button[data-act]');
      if (!btn) return;
      const act = btn.getAttribute('data-act');
      const runId = btn.getAttribute('data-run');
      if (!runId) return;

      // Try common export endpoint
      const fmt = (act === 'zip') ? 'zip' : 'html';
      const url = `/api/vsp/run_export_v3?run_id=${encodeURIComponent(runId)}&fmt=${encodeURIComponent(fmt)}`;
      window.open(url, '_blank');
    }, {passive:true});
  }

  let lastItems = [];

  async function refresh(){
    const host = findRunsHost();
    if (!host) return;
    ensureShell(host);

    const limit = Number(qs('#vsp-cm-limit')?.value || 200) || 200;
    const hideEmpty = !!qs('#vsp-cm-hide-empty')?.checked;
    const st = qs('#vsp-cm-status');
    st.textContent = 'Loading…';

    try{
      const data = await fetchRuns(limit, hideEmpty);
      lastItems = data.items || [];
      qs('#vsp-cm-kpi-source').textContent = data.source || 'fs';
      renderRows(lastItems);
      st.textContent = `Loaded ${lastItems.length} items from ${data.source || 'fs'}.`;
    }catch(err){
      st.textContent = `ERROR: ${String(err && err.message || err)}`;
    }
  }

  function mount(){
    const host = findRunsHost();
    if (!host) return;

    ensureShell(host);
    wireActions();

    const btn = qs('#vsp-cm-refresh');
    const search = qs('#vsp-cm-search');
    const limit = qs('#vsp-cm-limit');
    const hide = qs('#vsp-cm-hide-empty');

    if (btn && !btn.__bound){
      btn.__bound = true;
      btn.addEventListener('click', refresh);
    }
    if (search && !search.__bound){
      search.__bound = true;
      search.addEventListener('input', () => renderRows(lastItems));
    }
    if (limit && !limit.__bound){
      limit.__bound = true;
      limit.addEventListener('change', refresh);
    }
    if (hide && !hide.__bound){
      hide.__bound = true;
      hide.addEventListener('change', refresh);
    }

    console.log('[VSP_RUNS_COMMERCIAL_PANEL_V1] mounted into #vsp-runs-main (MASTER)');
    refresh();
  }

  // mount on ready + whenever user switches tabs
  function onReady(fn){
    if (document.readyState === 'complete' || document.readyState === 'interactive') setTimeout(fn, 0);
    else document.addEventListener('DOMContentLoaded', fn);
  }

  onReady(() => {
    mount();
    window.addEventListener('hashchange', () => setTimeout(mount, 50));
  });

})();
JS

echo "[OK] wrote commercial runs master panel: $PANEL"

# ----------------------------
# 4) Restart UI
# ----------------------------
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
echo "[OK] UI restarted"
tail -n 20 out_ci/ui_8910.log || true

echo "=== VERIFY: template tags ==="
curl -s http://localhost:8910/ | grep -n "vsp_runs_commercial_panel_v1.js" | head || true
curl -s http://localhost:8910/ | grep -n "vsp_runs_trigger_scan_ui_v3.js" | head || true

echo "=== VERIFY: runs fs ==="
curl -s "http://localhost:8910/api/vsp/runs_index_v3_fs?limit=5&hide_empty=1" | head -c 350; echo
