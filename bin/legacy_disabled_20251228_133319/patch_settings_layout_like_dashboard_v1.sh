#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/settings.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

BACKUP="$TPL.bak_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[i] Đã backup settings cũ -> $BACKUP"

cat > "$TPL" << 'HTML'
{% extends "base.html" %}

{% block title %}SECURITY BUNDLE – Settings{% endblock %}

{% block content %}
  <!-- Main content -->
  <div class="sb-main">
    <!-- Header giống Dashboard -->
    <div class="sb-main-header">
      <div>
        <div class="sb-main-title">Settings</div>
        <div class="sb-main-subtitle">
          Tool configuration loaded from <code>tool_config.json</code>.
        </div>
      </div>
      <div class="sb-pill-top-right">
        Config file:
        <code class="sb-pill-strong">{{ cfg_path }}</code>
      </div>
    </div>

    <!-- Thân trang: 1 card full-width giống Dashboard -->
    <div class="sb-main-body">
      <section class="sb-section sb-section-full">
        <div class="sb-section-header">
          <div class="sb-section-title">By tool / config</div>
          <div class="sb-section-subtitle">
            ON/OFF, level &amp; modes per tool.
            Các giá trị ở đây sẽ được dùng khi chạy CLI / CI/CD.
          </div>
        </div>

        <div class="sb-card sb-card-fill">
          <div class="sb-card-body">

            <div class="sb-help-line">
              <span class="sb-help-label">Source:</span>
              <code>static/last_tool_config.json</code>
            </div>

            <div class="sb-table-wrapper sb-table-wrapper-settings">
              <table class="sb-table sb-table-settings">
                <thead>
                  <tr>
                    <th>Tool</th>
                    <th>Enabled</th>
                    <th>Level</th>
                    <th>Modes</th>
                    <th>Notes</th>
                  </tr>
                </thead>
                <tbody>
                  {% for row in rows %}
                  <tr>
                    <td class="sb-col-tool">{{ row.tool }}</td>
                    <td class="sb-col-enabled">
                      {% if row.enabled %}
                        <span class="sb-tag sb-tag-on">true</span>
                      {% else %}
                        <span class="sb-tag sb-tag-off">false</span>
                      {% endif %}
                    </td>
                    <td class="sb-col-level">
                      <span class="sb-level-pill sb-level-{{ row.level|default('std')|lower }}">
                        {{ row.level|upper }}
                      </span>
                    </td>
                    <td class="sb-col-modes">
                      {{ row.modes }}
                    </td>
                    <td class="sb-col-notes">
                      {{ row.notes }}
                    </td>
                  </tr>
                  {% endfor %}
                </tbody>
              </table>
            </div>

          </div>
        </div>
      </section>
    </div>
  </div>
{% endblock %}
HTML

echo "[OK] Đã ghi lại templates/settings.html theo layout Dashboard."
