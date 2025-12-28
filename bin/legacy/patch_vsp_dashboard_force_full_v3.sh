#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"

TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
if [ ! -f "$TPL" ]; then
  TPL="$UI_ROOT/templates/vsp_5tabs_full.html"
fi

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template Dashboard 5 tab (vsp_dashboard_2025.html / vsp_5tabs_full.html)"
  exit 1
fi

BACKUP="${TPL}.bak_dashboard_full_v3_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

export TPL

python - << 'PY'
import os, pathlib, re

tpl = pathlib.Path(os.environ["TPL"])
html = tpl.read_text(encoding="utf-8")

# 1) Bỏ shim nếu còn
html_new = html.replace(
    '<script src="/static/js/vsp_api_shim_v1.js"></script>',
    '<!-- vsp_api_shim_v1.js removed by patch_vsp_dashboard_force_full_v3 -->'
)

# 2) Thêm CSS core (nếu chưa có)
if 'id="vsp-dashboard-core-css"' not in html_new:
    css_block = """
  <style id="vsp-dashboard-core-css">
    .vsp-dashboard-grid {
      display: grid;
      grid-template-columns: minmax(0, 2fr) minmax(0, 3fr);
      gap: 1.5rem;
      margin-top: 1.5rem;
    }
    @media (max-width: 1200px) {
      .vsp-dashboard-grid {
        grid-template-columns: minmax(0, 1fr);
      }
    }
    .vsp-kpi-zone,
    .vsp-chart-zone,
    .vsp-findings-zone {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }
    .vsp-card {
      background: #0b1020;
      border-radius: 0.9rem;
      border: 1px solid rgba(148, 163, 184, 0.18);
      padding: 1rem 1.25rem;
    }
    .vsp-card-soft {
      background: linear-gradient(135deg, rgba(15, 23, 42, 0.9), rgba(15, 23, 42, 0.7));
      border-color: rgba(148, 163, 184, 0.35);
    }
    .vsp-kpi-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
      gap: 0.75rem;
    }
    .vsp-kpi-label {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: #94a3b8;
      margin-bottom: 0.25rem;
    }
    .vsp-kpi-value {
      font-size: 1.4rem;
      font-weight: 600;
      color: #e5e7eb;
    }
    .vsp-kpi-sub {
      font-size: 0.78rem;
      color: #9ca3af;
      margin-top: 0.35rem;
    }
    .vsp-chart-row {
      display: grid;
      grid-template-columns: minmax(0, 80px) minmax(0, 1fr) minmax(0, 80px);
      align-items: center;
      gap: 0.5rem;
      margin-bottom: 0.4rem;
    }
    .vsp-chart-label {
      font-size: 0.78rem;
      color: #cbd5f5;
    }
    .vsp-chart-bar-wrap {
      background: #020617;
      border-radius: 999px;
      overflow: hidden;
      height: 6px;
    }
    .vsp-chart-bar {
      height: 100%;
      background: linear-gradient(90deg, #22c55e, #16a34a);
    }
    .vsp-chart-value {
      font-size: 0.78rem;
      color: #9ca3af;
      text-align: right;
      font-variant-numeric: tabular-nums;
    }
    .vsp-chart-empty {
      font-size: 0.8rem;
      color: #64748b;
    }
    .vsp-empty {
      padding: 1.5rem;
      text-align: left;
    }
    .vsp-empty-title {
      font-size: 0.95rem;
      font-weight: 500;
      color: #e5e7eb;
    }
    .vsp-empty-subtitle {
      font-size: 0.8rem;
      color: #9ca3af;
      margin-top: 0.25rem;
    }
    .vsp-dashboard-title-row {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 1rem;
    }
    .vsp-dashboard-title-row small {
      font-size: 0.78rem;
      color: #94a3b8;
    }
    .vsp-score-badge {
      font-size: 1.2rem;
      font-weight: 600;
      color: #22c55e;
    }
    #vsp-dashboard-error {
      display: none;
      margin-top: 0.5rem;
      font-size: 0.8rem;
      color: #fecaca;
    }
  </style>
"""
    html_new = html_new.replace('</head>', css_block + '\n</head>')

# 3) Inject layout vào vsp-tab-dashboard
marker = 'id="vsp-tab-dashboard"'
i = html_new.find(marker)
if i == -1:
    print("[ERR] Không thấy id=\"vsp-tab-dashboard\" trong", tpl)
    tpl.write_text(html_new, encoding="utf-8")
    raise SystemExit(1)

j = html_new.find('>', i)
if j == -1:
    print("[ERR] Không tìm được '>' sau vsp-tab-dashboard trong", tpl)
    tpl.write_text(html_new, encoding="utf-8")
    raise SystemExit(1)

inject = """
  <div class="vsp-dashboard-title-row" style="margin-top:1rem;">
    <div>
      <h2 class="vsp-section-title">Security Posture Overview</h2>
      <p class="vsp-section-subtitle">CIO-level view của toàn bộ findings từ 8 tool (FULL_EXT).</p>
      <div id="vsp-dashboard-error"></div>
    </div>
    <div style="text-align:right; font-size:0.8rem; color:#9ca3af;">
      <div>Last run: <span id="vsp-last-run-span">—</span></div>
      <div>Score: <span id="vsp-kpi-score-main">—/100</span></div>
    </div>
  </div>

  <div class="vsp-dashboard-grid">
    <section class="vsp-kpi-zone">
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-kpi-grid">
          <div>
            <div class="vsp-kpi-label">Total Findings</div>
            <div class="vsp-kpi-value" id="vsp-kpi-total">—</div>
            <div class="vsp-kpi-sub">Tổng số findings hợp nhất từ tất cả tool.</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Critical</div>
            <div class="vsp-kpi-value" id="vsp-kpi-critical">—</div>
          </div>
          <div>
            <div class="vsp-kpi-label">High</div>
            <div class="vsp-kpi-value" id="vsp-kpi-high">—</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Medium</div>
            <div class="vsp-kpi-value" id="vsp-kpi-medium">—</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Low</div>
            <div class="vsp-kpi-value" id="vsp-kpi-low">—</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Info/Trace</div>
            <div class="vsp-kpi-value" id="vsp-kpi-info">—</div>
          </div>
        </div>
      </div>

      <div class="vsp-card">
        <div class="vsp-kpi-grid">
          <div>
            <div class="vsp-kpi-label">Top Risky Tool</div>
            <div class="vsp-kpi-value" id="vsp-kpi-top-tool">—</div>
            <div class="vsp-kpi-sub">Tool tạo nhiều CRITICAL/HIGH nhất.</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Most Impacted CWE</div>
            <div class="vsp-kpi-value" id="vsp-kpi-top-cwe">—</div>
          </div>
          <div>
            <div class="vsp-kpi-label">Top Vulnerable Module</div>
            <div class="vsp-kpi-value" id="vsp-kpi-top-module">—</div>
          </div>
        </div>
      </div>
    </section>

    <section class="vsp-chart-zone">
      <div class="vsp-card vsp-card-soft">
        <div class="vsp-kpi-label" style="margin-bottom:0.5rem;">Severity Distribution</div>
        <div id="vsp-chart-severity"></div>
      </div>

      <div class="vsp-card">
        <div class="vsp-kpi-label" style="margin-bottom:0.5rem;">Critical/High by Tool</div>
        <div id="vsp-chart-tool" class="vsp-chart-body"></div>
      </div>

      <div class="vsp-card">
        <div class="vsp-kpi-label" style="margin-bottom:0.5rem;">Top CWE Exposure</div>
        <div id="vsp-chart-cwe" class="vsp-chart-body"></div>
      </div>
    </section>
  </div>
"""

if 'id="vsp-kpi-total"' not in html_new:
    html_new = html_new[:j+1] + inject + html_new[j+1:]
    print("[OK] Injected dashboard layout into vsp-tab-dashboard")
else:
    print("[INFO] Dashboard layout đã tồn tại – không inject thêm")

# 4) Đảm bảo script KPI & CHARTS được load
scripts = [
    '<script src="/static/js/vsp_dashboard_kpi_v1.js"></script>',
    '<script src="/static/js/vsp_dashboard_charts_v1.js"></script>',
]
for s in scripts:
    if s not in html_new:
        html_new = html_new.replace('</body>', f'  {s}\n</body>')
        print("[OK] Thêm", s, "vào cuối template")
    else:
        print("[INFO]", s, "đã tồn tại – bỏ qua")

tpl.write_text(html_new, encoding="utf-8")
PY
