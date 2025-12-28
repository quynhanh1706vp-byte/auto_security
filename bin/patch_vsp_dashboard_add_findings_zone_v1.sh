#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_findings_zone_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
from pathlib import Path

tpl_path = Path("templates/vsp_dashboard_2025.html")
html = tpl_path.read_text(encoding="utf-8")

marker = "</body>"
if marker not in html:
    raise SystemExit("[ERR] Không tìm thấy </body> trong vsp_dashboard_2025.html")

block = """
  <!-- === DASHBOARD FINDINGS ZONE (Top risks / noisy / CVE / by tool) === -->
  <section id="vsp-dashboard-findings-zone" class="vsp-section vsp-section-stack">
    <div class="vsp-section-header">
      <div>
        <h2 class="vsp-section-title">Findings zone</h2>
        <p class="vsp-section-subtitle">
          Top risky findings, noisy paths, exploited CVEs và phân bổ severity theo tool.
        </p>
      </div>
      <div class="vsp-section-meta">
        <span class="vsp-chip vsp-chip-soft" id="vsp-dash-findings-run-label">
          Run: (latest)
        </span>
      </div>
    </div>

    <div class="vsp-grid vsp-grid-4">
      <!-- Top risky findings -->
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-card-header">
          <h3 class="vsp-card-title">Top risky findings</h3>
          <p class="vsp-card-subtitle">Các phát hiện có severity cao, ưu tiên xử lý.</p>
        </div>
        <div class="vsp-card-body">
          <table class="vsp-table-compact">
            <thead>
              <tr>
                <th>Sev</th>
                <th>Tool</th>
                <th>Message</th>
                <th>Path</th>
              </tr>
            </thead>
            <tbody id="vsp-dash-top-risky-tbody">
              <tr>
                <td colspan="4" class="vsp-table-empty">No data</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Noisy paths -->
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-card-header">
          <h3 class="vsp-card-title">Noisy paths</h3>
          <p class="vsp-card-subtitle">File / thư mục sinh nhiều findings nhất.</p>
        </div>
        <div class="vsp-card-body">
          <table class="vsp-table-compact">
            <thead>
              <tr>
                <th>Path</th>
                <th>Findings</th>
              </tr>
            </thead>
            <tbody id="vsp-dash-noisy-paths-tbody">
              <tr>
                <td colspan="2" class="vsp-table-empty">No data</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Exploited CVEs -->
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-card-header">
          <h3 class="vsp-card-title">Top exploited CVEs</h3>
          <p class="vsp-card-subtitle">CVE xuất hiện nhiều và severity cao.</p>
        </div>
        <div class="vsp-card-body">
          <table class="vsp-table-compact">
            <thead>
              <tr>
                <th>CVE</th>
                <th>Sev</th>
                <th>Count</th>
              </tr>
            </thead>
            <tbody id="vsp-dash-top-cves-tbody">
              <tr>
                <td colspan="3" class="vsp-table-empty">No data</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- By tool severity -->
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-card-header">
          <h3 class="vsp-card-title">By tool</h3>
          <p class="vsp-card-subtitle">Phân bổ CRIT/HIGH/MED/LOW/INFO/TRACE theo tool.</p>
        </div>
        <div class="vsp-card-body">
          <table class="vsp-table-compact">
            <thead>
              <tr>
                <th>Tool</th>
                <th>C</th>
                <th>H</th>
                <th>M</th>
                <th>L</th>
                <th>I</th>
                <th>T</th>
                <th>Total</th>
              </tr>
            </thead>
            <tbody id="vsp-dash-by-tool-tbody">
              <tr>
                <td colspan="8" class="vsp-table-empty">No data</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </section>

  <!-- JS: Dashboard findings renderer -->
  <script src="/static/js/vsp_dashboard_findings_v1.js"></script>
"""

html = html.replace(marker, block + "\n</body>")
tpl_path.write_text(html, encoding="utf-8")
print("[PATCH] Đã chèn Findings zone + script vsp_dashboard_findings_v1.js trước </body>")
PY

echo "[DONE] Patch vsp_dashboard_add_findings_zone_v1 hoàn tất."
