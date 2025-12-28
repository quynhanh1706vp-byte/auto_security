#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TPL="$ROOT/templates/settings.html"
CSS="$ROOT/static/css/security_resilient.css"

# ---------- 1) Patch settings.html ----------
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

BKP_TPL="$TPL.bak_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BKP_TPL"
echo "[i] Backup settings.html -> $BKP_TPL"

cat > "$TPL" << 'HTML'
{% extends "base.html" %}

{% block title %}SECURITY BUNDLE – Settings{% endblock %}

{% block content %}
  <div class="sb-main">
    <!-- Header: chỉ giữ title, không subtitle dài -->
    <div class="sb-main-header">
      <div class="sb-main-title">Settings</div>
    </div>

    <div class="sb-main-body">
      <section class="sb-section sb-section-full">
        <div class="sb-section-header">
          <div class="sb-section-title">By tool / config</div>
        </div>

        <div class="sb-card sb-card-fill">
          <div class="sb-card-body">
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
                    <td class="sb-col-modes">{{ row.modes }}</td>
                    <td class="sb-col-notes">{{ row.notes }}</td>
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

echo "[OK] Đã ghi lại settings.html (header gọn, không còn text 'Tool configuration...' và 'ON/OFF...')."

# ---------- 2) Patch CSS: nav active = xanh lá ----------
if [ ! -f "$CSS" ]; then
  echo "[WARN] Không tìm thấy $CSS để patch màu nav, bỏ qua CSS." >&2
  exit 0
fi

BKP_CSS="$CSS.bak_$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "$BKP_CSS"
echo "[i] Backup security_resilient.css -> $BKP_CSS"

cat >> "$CSS" << 'CSS'


/* === OVERRIDE: nav item đang active dùng màu xanh lá (ghi đè rule tím cũ) === */
.sidebar .nav-item.active > a,
.sidebar .nav-item > a.active,
.nav .nav-item.active > a {
  background: linear-gradient(90deg, #28a745, #22c55e) !important;
  border-color: #22c55e !important;
  color: #f8fafc !important;
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.35) !important;
}
CSS

echo "[OK] Đã append CSS override cho nav active = màu xanh lá."
