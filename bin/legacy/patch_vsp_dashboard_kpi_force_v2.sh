#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_KPI_FORCE_V2]"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX TPL    = $TPL"

if [ ! -f "$TPL" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $TPL"
  exit 1
fi

# Nếu đã patch rồi thì thôi
if grep -q "VSP_DASHBOARD_KPI_FORCE_V2" "$TPL"; then
  echo "$LOG_PREFIX Đã thấy marker VSP_DASHBOARD_KPI_FORCE_V2 – bỏ qua."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TPL.bak_kpi_force_v2_$TS"
cp "$TPL" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $TPL -> $BACKUP"

python - "$TPL" << 'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

snippet = """
    <!-- VSP_DASHBOARD_KPI_FORCE_V2 -->
    <script>
      document.addEventListener('DOMContentLoaded', function () {
        const log = (...args) => console.log('[VSP_KPI_FORCE_V2]', ...args);

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

            const score = (data.security_posture_score !== undefined && data.security_posture_score !== null)
              ? data.security_posture_score
              : '-';
            setText('vsp-kpi-score', score, '/100');

            if (data.top_risky_tool) {
              setText('vsp-kpi-top-tool', data.top_risky_tool.label || data.top_risky_tool.id || '-', '');
            }
            if (data.top_impacted_cwe) {
              setText('vsp-kpi-top-cwe', data.top_impacted_cwe.label || data.top_impacted_cwe.id || '-', '');
            }
            if (data.top_vulnerable_module) {
              setText('vsp-kpi-top-module', data.top_vulnerable_module.label || data.top_vulnerable_module.id || '-', '');
            }

            // Header + footer
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
            console.error('[VSP_KPI_FORCE_V2] error loading dashboard_v3', err);
          });
      });
    </script>
"""

marker = "</body>"
if marker not in html:
    print("[VSP_KPI_FORCE_V2] [ERR] Không tìm thấy </body> trong template")
    sys.exit(1)

html = html.replace(marker, snippet + "\n  " + marker)
path.write_text(html, encoding="utf-8")
print("[VSP_KPI_FORCE_V2] Injected KPI force script before </body>.")
PY

echo "$LOG_PREFIX [DONE] Đã inject script KPI force vào $TPL"
