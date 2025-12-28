#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_BIND_DATA_V3]"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX TPL    = $TPL"

if [ ! -f "$TPL" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $TPL"
  exit 1
fi

# tránh chèn trùng
if grep -q "VSP_KPI_FORCE_V3" "$TPL"; then
  echo "$LOG_PREFIX Found marker VSP_KPI_FORCE_V3 – skip."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TPL.bak_bind_data_v3_$TS"
cp "$TPL" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $TPL -> $BACKUP"

python - "$TPL" << 'PY'
import pathlib, sys

p = pathlib.Path(sys.argv[1])
html = p.read_text(encoding="utf-8")

marker = "</body>"
if marker not in html:
    print("[VSP_BIND_DATA_V3] [ERR] Không tìm thấy </body> trong template")
    sys.exit(1)

snippet = r"""
    <!-- VSP_KPI_FORCE_V3 – bind Dashboard KPI + header/footer -->
    <script>
      document.addEventListener('DOMContentLoaded', function () {
        const log = (...args) => console.log('[VSP_KPI_FORCE_V3]', ...args);

        function setText(id, value, suffix) {
          const el = document.getElementById(id);
          if (!el) return;
          if (value === null || value === undefined || value === '-') {
            el.textContent = '-';
          } else {
            el.textContent = String(value) + (suffix || '');
          }
        }

        fetch('/api/vsp/dashboard_v3')
          .then(r => r.json())
          .then(data => {
            log('Dashboard data', data);
            const sev = data.severity_cards || {};

            setText('vsp-kpi-total-findings', data.total_findings);
            setText('vsp-kpi-critical', sev.CRITICAL || 0);
            setText('vsp-kpi-high', sev.HIGH || 0);
            setText('vsp-kpi-medium', sev.MEDIUM || 0);
            setText('vsp-kpi-low', sev.LOW || 0);

            const infoCount  = sev.INFO  || 0;
            const traceCount = sev.TRACE || 0;
            setText('vsp-kpi-info-trace', infoCount + traceCount);

            const scoreVal = (data.security_posture_score !== undefined && data.security_posture_score !== null)
              ? data.security_posture_score
              : '-';
            setText('vsp-kpi-score', scoreVal, '/100');

            if (data.top_risky_tool) {
              setText('vsp-kpi-top-tool', data.top_risky_tool.label || data.top_risky_tool.id || '-', '');
            }
            if (data.top_impacted_cwe) {
              setText('vsp-kpi-top-cwe', data.top_impacted_cwe.label || data.top_impacted_cwe.id || '-', '');
            }
            if (data.top_vulnerable_module) {
              setText('vsp-kpi-top-module', data.top_vulnerable_module.label || data.top_vulnerable_module.id || '-', '');
            }

            if (data.latest_run_id) {
              setText('vsp-last-run-header', data.latest_run_id, '');
              const footer = document.getElementById('vsp-last-run-footer');
              if (footer) footer.textContent = 'Last run: ' + data.latest_run_id;
            }

            const scoreHeader = (data.security_posture_score !== undefined && data.security_posture_score !== null)
              ? data.security_posture_score
              : '-';
            setText('vsp-last-score-header', scoreHeader, '/100');
          })
          .catch(err => {
            console.error('[VSP_KPI_FORCE_V3] error loading dashboard_v3', err);
          });
      });
    </script>

    <!-- VSP_TABS_FORCE_V2 – bind Runs / Data Source / Settings / Rules -->
    <script>
      document.addEventListener('DOMContentLoaded', function () {
        const log = (...args) => console.log('[VSP_TABS_FORCE_V2]', ...args);

        function ensureTableHeader(tableEl, headers) {
          if (!tableEl) return;
          tableEl.innerHTML = '';
          const thead = document.createElement('thead');
          const tr = document.createElement('tr');
          headers.forEach(h => {
            const th = document.createElement('th');
            th.textContent = h;
            tr.appendChild(th);
          });
          thead.appendChild(tr);
          tableEl.appendChild(thead);
          const tbody = document.createElement('tbody');
          tableEl.appendChild(tbody);
          return tbody;
        }

        // Runs
        function loadRunsBasic() {
          const table = document.getElementById('vsp-runs-table');
          if (!table) { log('Không thấy #vsp-runs-table'); return; }

          fetch('/api/vsp/runs_index_v3?limit=50')
            .then(r => r.json())
            .then(data => {
              log('Runs data', data);
              let runs = [];
              if (Array.isArray(data)) runs = data;
              else if (Array.isArray(data.items)) runs = data.items;
              else if (Array.isArray(data.runs)) runs = data.runs;

              const tbody = ensureTableHeader(table, ['Run ID', 'Started at', 'Total findings', 'CRIT+HIGH']);
              if (!tbody) return;

              if (!runs || runs.length === 0) {
                const tr = document.createElement('tr');
                const td = document.createElement('td');
                td.colSpan = 4;
                td.textContent = 'No runs found.';
                tr.appendChild(td);
                tbody.appendChild(tr);
                return;
              }

              runs.slice(0, 50).forEach(run => {
                const tr = document.createElement('tr');

                const runId = run.run_id || run.id || '-';
                const started = run.started_at || run.started || run.created_at || '-';
                const total = run.total_findings ?? run.findings_total ?? '-';

                const bySev = run.by_severity || run.summary_by_severity || {};
                const crit = bySev.CRITICAL || 0;
                const high = bySev.HIGH || 0;
                const critHigh = (crit || 0) + (high || 0);

                [runId, started, total, critHigh].forEach((val, idx) => {
                  const td = document.createElement('td');
                  if (idx === 3) {
                    const span = document.createElement('span');
                    span.className = 'vsp-pill vsp-pill-crit';
                    span.textContent = String(val);
                    td.appendChild(span);
                  } else {
                    td.textContent = (val === null || val === undefined) ? '-' : String(val);
                  }
                  tr.appendChild(td);
                });
                tbody.appendChild(tr);
              });
            })
            .catch(err => {
              console.error('[VSP_TABS_FORCE_V2] error loading runs_index_v3', err);
            });
        }

        // Data Source
        function loadDataSourceBasic() {
          const table = document.getElementById('vsp-ds-table');
          if (!table) { log('Không thấy #vsp-ds-table'); return; }

          fetch('/api/vsp/datasource_v2?limit=50')
            .then(r => r.json())
            .then(data => {
              log('Datasource data', data);
              let items = [];
              if (Array.isArray(data)) items = data;
              else if (Array.isArray(data.items)) items = data.items;

              const tbody = ensureTableHeader(
                table,
                ['Severity', 'Tool', 'Rule / CWE / ID', 'Location / Path']
              );
              if (!tbody) return;

              if (!items || items.length === 0) {
                const tr = document.createElement('tr');
                const td = document.createElement('td');
                td.colSpan = 4;
                td.textContent = 'No findings.';
                tr.appendChild(td);
                tbody.appendChild(tr);
                return;
              }

              items.slice(0, 50).forEach(f => {
                const tr = document.createElement('tr');

                const sev = f.severity || '-';
                const tool = f.tool || f.source || f.scanner || '-';
                const rule = f.rule_id || f.rule || f.cwe || f.vuln_id || f.id || '-';
                const loc = f.location || f.file || f.filepath || f.path || '-';

                const sevTd = document.createElement('td');
                const pill = document.createElement('span');
                let cls = 'vsp-pill ';
                switch (String(sev).toUpperCase()) {
                  case 'CRITICAL': cls += 'vsp-pill-crit'; break;
                  case 'HIGH': cls += 'vsp-pill-high'; break;
                  case 'MEDIUM': cls += 'vsp-pill-med'; break;
                  case 'LOW': cls += 'vsp-pill-low'; break;
                  case 'INFO': cls += 'vsp-pill-info'; break;
                  case 'TRACE': cls += 'vsp-pill-trace'; break;
                  default: cls += 'vsp-pill-trace'; break;
                }
                pill.className = cls;
                pill.textContent = sev;
                sevTd.appendChild(pill);
                tr.appendChild(sevTd);

                [tool, rule, loc].forEach(val => {
                  const td = document.createElement('td');
                  td.textContent = (val === null || val === undefined) ? '-' : String(val);
                  tr.appendChild(td);
                });

                tbody.appendChild(tr);
              });
            })
            .catch(err => {
              console.error('[VSP_TABS_FORCE_V2] error loading datasource_v2', err);
            });
        }

        // Settings
        function loadSettingsBasic() {
          const root = document.getElementById('vsp-settings-root');
          if (!root) { log('Không thấy #vsp-settings-root'); return; }

          fetch('/api/vsp/settings_ui_v1')
            .then(r => r.json())
            .then(data => {
              log('Settings data', data);
              const settings = data.settings || data || {};
              const pre = document.createElement('pre');
              pre.style.fontSize = '11px';
              pre.style.color = '#e5e7eb';
              pre.style.background = 'rgba(15,23,42,0.9)';
              pre.style.borderRadius = '12px';
              pre.style.padding = '10px 12px';
              pre.textContent = JSON.stringify(settings, null, 2);
              root.innerHTML = '';
              root.appendChild(pre);
            })
            .catch(err => {
              console.error('[VSP_TABS_FORCE_V2] error loading settings_ui_v1', err);
            });
        }

        // Rules
        function loadRulesBasic() {
          const root = document.getElementById('vsp-rules-root');
          if (!root) { log('Không thấy #vsp-rules-root'); return; }

          fetch('/api/vsp/rule_overrides_ui_v1')
            .then(r => r.json())
            .then(data => {
              log('Rules data', data);
              const overrides = data.overrides || data.items || [];

              if (!overrides || overrides.length === 0) {
                root.innerHTML = '<p style="font-size:12px; color:#9ca3af;">No rule overrides defined yet.</p>';
                return;
              }

              const table = document.createElement('table');
              table.className = 'vsp-table';

              const thead = document.createElement('thead');
              const htr = document.createElement('tr');
              ['Rule / ID', 'Action', 'New severity', 'Note'].forEach(h => {
                const th = document.createElement('th');
                th.textContent = h;
                htr.appendChild(th);
              });
              thead.appendChild(htr);
              table.appendChild(thead);

              const tbody = document.createElement('tbody');
              overrides.forEach(o => {
                const tr = document.createElement('tr');
                const rule = o.rule_id || o.id || o.pattern || '-';
                const action = o.action || o.mode || '-';
                const newSev = o.new_severity || o.severity || '-';
                const note = o.note || o.reason || '';

                [rule, action, newSev, note].forEach((val, idx) => {
                  const td = document.createElement('td');
                  if (idx === 2) {
                    const span = document.createElement('span');
                    span.className = 'vsp-pill vsp-pill-' + String(val).toLowerCase();
                    span.textContent = val;
                    td.appendChild(span);
                  } else {
                    td.textContent = (val === null || val === undefined) ? '-' : String(val);
                  }
                  tr.appendChild(td);
                });
                tbody.appendChild(tr);
              });
              table.appendChild(tbody);

              const wrapper = document.createElement('div');
              wrapper.className = 'vsp-table-wrapper';
              wrapper.appendChild(table);

              root.innerHTML = '';
              root.appendChild(wrapper);
            })
            .catch(err => {
              console.error('[VSP_TABS_FORCE_V2] error loading rule_overrides_ui_v1', err);
            });
        }

        loadRunsBasic();
        loadDataSourceBasic();
        loadSettingsBasic();
        loadRulesBasic();
      });
    </script>
"""

html = html.replace(marker, snippet + "\n  " + marker)
p.write_text(html, encoding="utf-8")
print("[VSP_BIND_DATA_V3] Injected KPI + tabs scripts.")
PY

echo "$LOG_PREFIX [DONE] Injected KPI + tabs binding scripts vào $TPL"
