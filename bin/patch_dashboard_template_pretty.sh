#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy templates/index.html"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

marker_start = "DASHBOARD – SEVERITY BUCKETS: CRITICAL / HIGH / MEDIUM / LOW"
marker_trend = "TREND – LAST RUNS"

i = html.find(marker_start)
j = html.find(marker_trend)

if i == -1 or j == -1:
    print("[ERR] Không tìm thấy marker DASHBOARD/TREND trong index.html")
    sys.exit(1)

before = html[:i]
after_trend = html[j:]  # sẽ giữ lại tiêu đề TREND – LAST RUNS trong block mới

new_block = """DASHBOARD – SEVERITY BUCKETS: CRITICAL / HIGH / MEDIUM / LOW
        </h3>

        <div class="dash-section">
          {% if dashboard.has_data and dashboard.last_run %}
          <div class="dash-metrics-grid">
            <div class="dash-metric-card">
              <div class="dash-metric-label">TOTAL FINDINGS</div>
              <div class="dash-metric-value">{{ dashboard.last_run.total }}</div>
              <div class="dash-metric-sub">
                Across all tools<br>
                {{ dashboard.last_run.run_id }}
              </div>
            </div>

            <div class="dash-metric-card">
              <div class="dash-metric-label">CRITICAL / HIGH</div>
              <div class="dash-metric-value">
                {{ dashboard.last_run.crit }}/{{ dashboard.last_run.high }}
              </div>
              <div class="dash-metric-sub">by severity</div>
            </div>

            <div class="dash-metric-card">
              <div class="dash-metric-label">LAST UPDATED</div>
              <div class="dash-metric-sub">
                {{ dashboard.last_run.last_updated_str }}<br>
                RUN folder: {{ dashboard.last_run.run_id }}
              </div>
            </div>
          </div>

          <div class="dash-severity-card">
            <div class="dash-severity-bars">
              <div class="dash-sev-bar">
                <div class="dash-sev-label crit">CRITICAL</div>
                <div class="dash-sev-bar-inner"
                     style="--sev-count: {{ dashboard.last_run.crit|default(0) }};"></div>
                <div class="dash-sev-count">{{ dashboard.last_run.crit }}</div>
              </div>
              <div class="dash-sev-bar">
                <div class="dash-sev-label high">HIGH</div>
                <div class="dash-sev-bar-inner"
                     style="--sev-count: {{ dashboard.last_run.high|default(0) }};"></div>
                <div class="dash-sev-count">{{ dashboard.last_run.high }}</div>
              </div>
              <div class="dash-sev-bar">
                <div class="dash-sev-label med">MEDIUM</div>
                <div class="dash-sev-bar-inner"
                     style="--sev-count: {{ dashboard.last_run.medium|default(0) }};"></div>
                <div class="dash-sev-count">{{ dashboard.last_run.medium }}</div>
              </div>
              <div class="dash-sev-bar">
                <div class="dash-sev-label low">LOW</div>
                <div class="dash-sev-bar-inner"
                     style="--sev-count: {{ dashboard.last_run.low|default(0) }};"></div>
                <div class="dash-sev-count">{{ dashboard.last_run.low }}</div>
              </div>
            </div>
          </div>
          {% else %}
          <p class="dash-empty-hint">
            Chưa có lần quét nào trong <code>out/RUN_*</code>. Hãy chạy bundle trước rồi reload Dashboard.
          </p>
          {% endif %}
        </div>

        <div class="dash-bottom-grid">
          <div class="dash-bottom-card">
            <h3>TOP RISK FINDINGS (CRITICAL / HIGH – MAX 10)</h3>
            {% if dashboard.top_risks %}
            <div class="dash-table-wrapper">
              <table class="dash-table">
                <thead>
                  <tr>
                    <th>Severity</th>
                    <th>Tool</th>
                    <th>Rule</th>
                    <th>Location</th>
                    <th>Message</th>
                  </tr>
                </thead>
                <tbody>
                  {% for f in dashboard.top_risks %}
                  <tr>
                    <td class="sev-pill {{ f.severity|lower }}">{{ f.severity }}</td>
                    <td>{{ f.tool }}</td>
                    <td>{{ f.rule_id }}</td>
                    <td class="mono small">{{ f.location }}</td>
                    <td class="small">{{ f.message }}</td>
                  </tr>
                  {% endfor %}
                </tbody>
              </table>
            </div>
            {% else %}
            <p class="dash-empty-hint">Chưa có dữ liệu để tổng hợp rủi ro.</p>
            {% endif %}
          </div>

          <div class="dash-bottom-card">
            <h3>TREND – LAST RUNS</h3>
            <div class="dash-table-wrapper">
              <table class="dash-table">
                <thead>
                  <tr>
                    <th>RUN</th>
                    <th class="right">TOTAL</th>
                    <th class="right">CRIT/HIGH</th>
                  </tr>
                </thead>
                <tbody>
                  {% for r in dashboard.runs|reverse %}
                  <tr>
                    <td class="mono small">{{ r.run_id }}</td>
                    <td class="right">
                      {% if r.total is not none %}
                        {{ r.total }}
                      {% else %}
                        –
                      {% endif %}
                    </td>
                    <td class="right">{{ r.crit }}/{{ r.high }}</td>
                  </tr>
                  {% endfor %}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Phần sau Dashboard giữ nguyên -->
"""

new_html = before + new_block + after_trend

with open(path, "w", encoding="utf-8") as f:
    f.write(new_html)

print("[OK] Đã patch Dashboard template (pretty).")
PY
