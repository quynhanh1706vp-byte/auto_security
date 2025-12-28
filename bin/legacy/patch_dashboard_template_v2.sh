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

new_block = """DASHBOARD – SEVERITY BUCKETS: CRITICAL / HIGH / MEDIUM / LOW
        </h3>

        {% if dashboard.has_data and dashboard.last_run %}
        <div class="dash-grid">
          <div class="dash-card">
            <div class="dash-card-title">TOTAL FINDINGS</div>
            <div class="dash-card-value">{{ dashboard.last_run.total }}</div>
            <div class="dash-card-sub">
              Across all tools<br>
              {{ dashboard.last_run.run_id }}
            </div>
          </div>

          <div class="dash-card">
            <div class="dash-card-title">CRITICAL / HIGH</div>
            <div class="dash-card-value">
              {{ dashboard.last_run.crit }}/{{ dashboard.last_run.high }}
            </div>
            <div class="dash-card-sub">by severity</div>
          </div>

          <div class="dash-card">
            <div class="dash-card-title">LAST UPDATED</div>
            <div class="dash-card-sub">
              {{ dashboard.last_run.last_updated_str }}<br>
              RUN folder: {{ dashboard.last_run.run_id }}
            </div>
          </div>
        </div>

        <div class="dash-bars">
          <div class="bar-item">
            <div class="bar-label">CRITICAL</div>
            <div class="bar-value">{{ dashboard.last_run.crit }}</div>
          </div>
          <div class="bar-item">
            <div class="bar-label">HIGH</div>
            <div class="bar-value">{{ dashboard.last_run.high }}</div>
          </div>
          <div class="bar-item">
            <div class="bar-label">MEDIUM</div>
            <div class="bar-value">{{ dashboard.last_run.medium }}</div>
          </div>
          <div class="bar-item">
            <div class="bar-label">LOW</div>
            <div class="bar-value">{{ dashboard.last_run.low }}</div>
          </div>
        </div>
        {% else %}
        <p>Chưa có lần quét nào trong out/RUN_*. Hãy chạy bundle trước rồi reload Dashboard.</p>
        {% endif %}

        <div class="dash-two-cols">
          <div class="dash-block">
            <h3>TOP RISK FINDINGS (CRITICAL / HIGH – MAX 10)</h3>
            {% if dashboard.top_risks %}
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
                  <td>{{ f.severity }}</td>
                  <td>{{ f.tool }}</td>
                  <td>{{ f.rule_id }}</td>
                  <td>{{ f.location }}</td>
                  <td>{{ f.message }}</td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
            {% else %}
            <p>Chưa có dữ liệu để tổng hợp rủi ro.</p>
            {% endif %}
          </div>

          <div class="dash-block">
            <h3>TREND – LAST RUNS</h3>
            <table class="dash-table">
              <thead>
                <tr>
                  <th>RUN</th>
                  <th>TOTAL</th>
                  <th>CRIT/HIGH</th>
                </tr>
              </thead>
              <tbody>
                {% for r in dashboard.runs|reverse %}
                <tr>
                  <td>{{ r.run_id }}</td>
                  <td>{% if r.total is not none %}{{ r.total }}{% else %}–{% endif %}</td>
                  <td>{{ r.crit }}/{{ r.high }}</td>
                </tr>
                {% endfor %}
              </tbody>
            </table>
          </div>
        </div>

        <!-- Giữ nguyên phần sau TREND – LAST RUNS như cũ -->
"""

after = html[j:]

new_html = before + new_block + after

with open(path, "w", encoding="utf-8") as f:
    f.write(new_html)

print("[OK] Đã patch block Dashboard trong index.html")
PY
