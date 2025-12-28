#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_UI_RESTORE_FULL]"
BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

echo "$LOG_PREFIX UI_ROOT = $UI_ROOT"
echo "$LOG_PREFIX TPL    = $TPL"

if [ ! -f "$TPL" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$TPL.bak_restore_full_$TS"
cp "$TPL" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $TPL -> $BACKUP"

cat > "$TPL" << 'HTML'
<!doctype html>
<html lang="vi">
  <head>
    <meta charset="UTF-8">
    <title>VersaSecure Platform – VSP 2025</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <script src="/static/js/vsp_console_patch_v1.js"></script>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">

    <link rel="stylesheet" href="{{ url_for('static', filename='css/vsp_2025_dark.css') }}">
  </head>
  <body class="vsp-theme">
    <div class="vsp-shell">

      <!-- SIDEBAR -->
      <aside class="vsp-shell-sidebar">
        <div class="vsp-shell-brand">
          <div class="vsp-shell-brand-badge">V</div>
          <div>
            VersaSecure Platform<br>
            <span style="font-size:11px; color:#9ca3af;">Security Bundle 2025</span>
          </div>
        </div>

        <div class="vsp-shell-tabs">
          <button class="vsp-shell-tab-btn is-active" data-tab="#vsp-tab-dashboard">
            <span class="dot"></span> Dashboard
          </button>
          <button class="vsp-shell-tab-btn" data-tab="#vsp-tab-runs">
            <span class="dot"></span> Runs & Reports
          </button>
          <button class="vsp-shell-tab-btn" data-tab="#vsp-tab-datasource">
            <span class="dot"></span> Data Source
          </button>
          <button class="vsp-shell-tab-btn" data-tab="#vsp-tab-settings">
            <span class="dot"></span> Settings
          </button>
          <button class="vsp-shell-tab-btn" data-tab="#vsp-tab-rules">
            <span class="dot"></span> Rule Overrides
          </button>
        </div>

        <div class="vsp-shell-footer">
          VSP 2025 • FULL_EXT<br>
          <span id="vsp-last-run-footer">Last run: —</span>
        </div>
      </aside>

      <!-- MAIN -->
      <main class="vsp-shell-main">
        <div class="vsp-shell-header-row">
          <div class="vsp-shell-title">
            <h1>Security Posture Overview</h1>
            <p>CIO-level view của toàn bộ findings từ 8 tool (FULL_EXT).</p>
          </div>
          <div class="vsp-shell-header-kpi">
            <div>
              <span class="label">Last run</span><br>
              <span class="value" id="vsp-last-run-header">—</span>
            </div>
            <div>
              <span class="label">Score</span><br>
              <span class="value" id="vsp-last-score-header">—/100</span>
            </div>
          </div>
        </div>

        <div class="vsp-tabs-content">

          <!-- TAB 1 – DASHBOARD -->
          <section id="vsp-tab-dashboard" class="vsp-tab-pane is-active">
            <div id="vsp-dashboard-kpi-zone">
              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Total findings</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-total-findings">-</div>
                  <div class="vsp-kpi-sub">All tools, all targets</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Critical</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-critical">-</div>
                  <div class="vsp-kpi-sub">Blocking issues</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">High</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-high">-</div>
                  <div class="vsp-kpi-sub">High-risk vulnerabilities</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Medium</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-medium">-</div>
                  <div class="vsp-kpi-sub">Medium severity findings</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Low</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-low">-</div>
                  <div class="vsp-kpi-sub">Low-priority issues</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Info + Trace</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-info-trace">-</div>
                  <div class="vsp-kpi-sub">Informational & trace findings</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Security posture score</div>
                  <div class="vsp-kpi-value">
                    <span id="vsp-kpi-score">-/100</span>
                  </div>
                  <div class="vsp-kpi-score-pill">
                    <span>Overall score</span>
                  </div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Top risky tool</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-top-tool">-</div>
                  <div class="vsp-kpi-sub">Tool with most CRIT/HIGH</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Top impacted CWE</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-top-cwe">-</div>
                  <div class="vsp-kpi-sub">Most frequent CWE across findings</div>
                </div>
              </div>

              <div class="vsp-kpi-card">
                <div class="vsp-kpi-card-inner">
                  <div class="vsp-kpi-label">Top vulnerable module</div>
                  <div class="vsp-kpi-value" id="vsp-kpi-top-module">-</div>
                  <div class="vsp-kpi-sub">Dependency with most severe findings</div>
                </div>
              </div>
            </div>

            <div class="vsp-charts-grid" style="margin-top:20px;">
              <div class="vsp-card">
                <div class="vsp-card-header">
                  <div class="vsp-card-title">Severity distribution & trend</div>
                  <div class="vsp-card-meta">Donut + CRIT/HIGH trend (from /api/vsp/dashboard_v3)</div>
                </div>
                <div id="vsp-dashboard-charts-main"></div>
              </div>

              <div class="vsp-card">
                <div class="vsp-card-header">
                  <div class="vsp-card-title">Top exposure overview</div>
                  <div class="vsp-card-meta">By tool / CWE / module</div>
                </div>
                <div id="vsp-dashboard-charts-side"></div>
              </div>
            </div>

            <div style="margin-top:20px;">
              <div class="vsp-card">
                <div class="vsp-card-header">
                  <div class="vsp-card-title">Priority & Compliance (placeholder)</div>
                  <div class="vsp-card-meta">
                    Zone này giữ layout bản thương mại; V2 sẽ mapping ISO 27001 / OWASP ASVS.
                  </div>
                </div>
                <p style="font-size:12px; color:#9ca3af; margin-top:6px;">
                  Nội dung mô tả mức độ tuân thủ, khuyến nghị remediation theo chuẩn ISO 27001 / OWASP ASVS
                  sẽ được hoàn thiện trong phiên bản V2. Hiện tại giữ layout để trình diễn bản thương mại V1.5.
                </p>
              </div>
            </div>
          </section>

          <!-- TAB 2 – RUNS -->
          <section id="vsp-tab-runs" class="vsp-tab-pane">
            <div class="vsp-card">
              <div class="vsp-card-header">
                <div class="vsp-card-title">Runs & Trend</div>
                <div class="vsp-card-meta">
                  Lịch sử runs từ summary_by_run.json • CRIT/HIGH trend theo thời gian.
                </div>
              </div>

              <div class="vsp-filters-row">
                <input class="vsp-input" id="vsp-runs-search" placeholder="Search by run id / tag...">
                <button class="vsp-button" id="vsp-runs-refresh">Refresh</button>
              </div>

              <div class="vsp-table-wrapper">
                <table class="vsp-table" id="vsp-runs-table"></table>
              </div>
            </div>

            <div style="margin-top:20px;">
              <div class="vsp-card">
                <div class="vsp-card-header">
                  <div class="vsp-card-title">Run trend (CRIT/HIGH)</div>
                  <div class="vsp-card-meta">
                    Vùng cho chart run trend (V2).
                  </div>
                </div>
                <div id="vsp-runs-trend"></div>
              </div>
            </div>
          </section>

          <!-- TAB 3 – DATA SOURCE -->
          <section id="vsp-tab-datasource" class="vsp-tab-pane">
            <div class="vsp-card">
              <div class="vsp-card-header">
                <div class="vsp-card-title">Findings Data Source</div>
                <div class="vsp-card-meta">
                  Unified findings_unified.json • filter & mini analytics.
                </div>
              </div>

            <div class="vsp-filters-row">
              <select class="vsp-select" id="vsp-ds-severity">
                <option value="">All severities</option>
                <option value="CRITICAL">Critical</option>
                <option value="HIGH">High</option>
                <option value="MEDIUM">Medium</option>
                <option value="LOW">Low</option>
                <option value="INFO">Info</option>
                <option value="TRACE">Trace</option>
              </select>
              <input class="vsp-input" id="vsp-ds-search" placeholder="Search in rule / path / CWE...">
            </div>

            <div class="vsp-table-wrapper">
              <table class="vsp-table" id="vsp-ds-table"></table>
            </div>
          </section>

          <!-- TAB 4 – SETTINGS -->
          <section id="vsp-tab-settings" class="vsp-tab-pane">
            <div class="vsp-card">
              <div class="vsp-card-header">
                <div class="vsp-card-title">Settings</div>
                <div class="vsp-card-meta">
                  Cấu hình tool / profile / rule mapping • /api/vsp/settings_ui_v1.
                </div>
              </div>
              <div id="vsp-settings-root">
                <p style="font-size:12px; color:#9ca3af;">
                  Settings sẽ hiển thị JSON cấu hình hiện tại, lấy từ /api/vsp/settings_ui_v1.
                </p>
              </div>
            </div>
          </section>

          <!-- TAB 5 – RULE OVERRIDES -->
          <section id="vsp-tab-rules" class="vsp-tab-pane">
            <div class="vsp-card">
              <div class="vsp-card-header">
                <div class="vsp-card-title">Rule Overrides</div>
                <div class="vsp-card-meta">
                  Quản lý ignore / downgrade / custom rule • /api/vsp/rule_overrides_ui_v1.
                </div>
              </div>
              <div id="vsp-rules-root">
                <p style="font-size:12px; color:#9ca3af;">
                  Nếu chưa có override, vùng này sẽ hiển thị thông báo "No rule overrides defined yet".
                </p>
              </div>
            </div>
          </section>

        </div>
      </main>
    </div>
  </body>
</html>
HTML

echo "$LOG_PREFIX [DONE] Đã ghi lại full layout cơ bản cho $TPL"
