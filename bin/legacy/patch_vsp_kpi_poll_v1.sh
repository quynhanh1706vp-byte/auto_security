#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_KPI_POLL_V1]"
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
if grep -q "VSP_KPI_POLL_V1" "$TPL"; then
  echo "$LOG_PREFIX Đã có marker VSP_KPI_POLL_V1 – bỏ qua."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TPL.bak_kpi_poll_$TS"
cp "$TPL" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $TPL -> $BACKUP"

python - "$TPL" << 'PY'
import pathlib, sys

p = pathlib.Path(sys.argv[1])
html = p.read_text(encoding="utf-8")

marker = "</body>"
if marker not in html:
    print("[VSP_KPI_POLL_V1] [ERR] Không tìm thấy </body> trong template")
    sys.exit(1)

snippet = r"""
    <!-- VSP_KPI_POLL_V1 – force KPI from /api/vsp/dashboard_v3 -->
    <script>
      document.addEventListener('DOMContentLoaded', function () {
        const log = (...args) => console.log('[VSP_KPI_POLL_V1]', ...args);

        function setText(id, value, suffix) {
          const el = document.getElementById(id);
          if (!el) return;
          if (value === null || value === undefined || value === '-') {
            el.textContent = '-';
          } else {
            el.textContent = String(value) + (suffix || '');
          }
        }

        function applyKpi(data) {
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
        }

        function updateOnce() {
          fetch('/api/vsp/dashboard_v3')
            .then(r => r.json())
            .then(data => {
              log('Dashboard data', data);
              applyKpi(data);
            })
            .catch(err => {
              console.error('[VSP_KPI_POLL_V1] error loading dashboard_v3', err);
            });
        }

        // Cập nhật ngay khi load + lặp lại mỗi 5s
        updateOnce();
        setInterval(updateOnce, 5000);
      });
    </script>
"""

html = html.replace(marker, snippet + "\n  " + marker)
p.write_text(html, encoding="utf-8")
print("[VSP_KPI_POLL_V1] Injected KPI poll script.")
PY

echo "$LOG_PREFIX [DONE] Đã inject KPI poll vào $TPL"
