#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_TABS_FORCE_V1]"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX TPL    = $TPL"

if [ ! -f "$TPL" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $TPL"
  exit 1
fi

# Tránh patch trùng
if grep -q "VSP_TABS_FORCE_CONTENT_V1" "$TPL"; then
  echo "$LOG_PREFIX Đã có marker VSP_TABS_FORCE_CONTENT_V1 – bỏ qua."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TPL.bak_tabs_force_$TS"
cp "$TPL" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $TPL -> $BACKUP"

python - "$TPL" << 'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

snippet = """
    <!-- VSP_TABS_FORCE_CONTENT_V1 -->
    <script>
      document.addEventListener('DOMContentLoaded', function () {
        const log = (...args) => console.log('[VSP_TABS_FORCE_V1]', ...args);

        // ===== Helpers =====
        function safeGet(obj, keys, fallback) {
          let cur = obj;
          for (const k of keys) {
            if (!cur || !(k in cur)) return fallback;
            cur = cur[k];
          }
          return cur ?? fallback;
        }

        function ensureTableHeader(tableEl, headers) {
          if (!tableEl) return;
          tableEl.innerHTML = '';
          const thead = document.createElement('thead');
          const tr = document.createElement('tr');
          for (const h of headers) {
            const th = document.createElement('th');
            th.textContent = h;
            tr.appendChild(th);
          }
          thead.appendChild(tr);
          tableEl.appendChild(thead);
          const tbody = document.createElement('tbody');
          tableEl.appendChild(tbody);
          return tbody;
        }

        // ===== Runs tab =====
        function loadRunsBasic() {
          const table = document.getElementById('vsp-runs-table');
          if (!table) { log('Không tìm thấy #vsp-runs-table'); return; }

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
                tbody.appendChild(tr);
                tr.appendChild(td);
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

                const cols = [runId, started, total, critHigh];

                cols.forEach((val, idx) => {
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
              console.error('[VSP_TABS_FORCE_V1] error loading runs_index_v3', err);
            });
        }

        // ===== Data Source tab =====
        function loadDataSourceBasic() {
          const table = document.getElementById('vsp-ds-table');
          if (!table) { log('Không tìm thấy #vsp-ds-table'); return; }

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

                // severity pill
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
              console.error('[VSP_TABS_FORCE_V1] error loading datasource_v2', err);
            });
        }

        // ===== Settings tab =====
        function loadSettingsBasic() {
          const root = document.getElementById('vsp-settings-root');
          if (!root) { log('Không tìm thấy #vsp-settings-root'); return; }

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
              console.error('[VSP_TABS_FORCE_V1] error loading settings_ui_v1', err);
            });
        }

        // ===== Rules tab =====
        function loadRulesBasic() {
          const root = document.getElementById('vsp-rules-root');
          if (!root) { log('Không tìm thấy #vsp-rules-root'); return; }

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
                    // severity pill
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
              console.error('[VSP_TABS_FORCE_V1] error loading rule_overrides_ui_v1', err);
            });
        }

        // Load tất cả ngay khi vào (đơn giản để demo V1.5)
        loadRunsBasic();
        loadDataSourceBasic();
        loadSettingsBasic();
        loadRulesBasic();
      });
    </script>
"""

marker = "</body>"
if marker not in html:
    print("[VSP_TABS_FORCE_V1] [ERR] Không tìm thấy </body> trong template")
    sys.exit(1)

html = html.replace(marker, snippet + "\n  " + marker)
path.write_text(html, encoding="utf-8")
print("[VSP_TABS_FORCE_V1] Injected tabs content script before </body>.")
PY

echo "$LOG_PREFIX [DONE] Đã inject script tabs force content vào $TPL"
