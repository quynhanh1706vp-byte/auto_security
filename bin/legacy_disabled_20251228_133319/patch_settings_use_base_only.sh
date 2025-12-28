#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/settings.html"

echo "[i] ROOT = $ROOT"
echo "[i] Template = $TPL"

# Backup bản cũ
if [ -f "$TPL" ]; then
  cp "$TPL" "${TPL}.bak_$(date +%Y%m%d_%H%M%S)"
  echo "[OK] Đã backup settings.html."
fi

# Ghi lại settings.html = chỉ còn extend base.html
cat > "$TPL" <<'HTML'
{% extends "base.html" %}

{% block title %}SECURITY_BUNDLE – Settings{% endblock %}

{% block content %}
<div class="sb-main sb-page-settings">
  <div class="sb-main-header">
    <div class="sb-main-title">Settings</div>
    <div class="sb-main-subtitle">
      By tool / config – bật/tắt tool, level và chế độ chạy.
    </div>
  </div>

  <div class="sb-card sb-card-settings">
    <div class="sb-card-header">
      <div class="sb-card-title">By tool / config</div>
      <div class="sb-card-subtitle">
        Bảng cấu hình từng tool (Enabled, Level, Modes, Notes).
      </div>
    </div>

    <div class="sb-table-wrapper sb-settings-table-wrapper">
      <table class="sb-table sb-settings-table">
        <thead>
          <tr>
            <th>TOOL</th>
            <th>ENABLED</th>
            <th>LEVEL</th>
            <th>MODES</th>
            <th>NOTES</th>
          </tr>
        </thead>
        <tbody id="sb-settings-body">
          {# Sau này JS fill dữ liệu vào đây #}
        </tbody>
      </table>
    </div>

    <div class="sb-settings-hint">
      Cấu hình thực tế đọc từ <code>tool_config.json</code>. 
      UI chỉ hiển thị ở đây để review nhanh.
    </div>
  </div>
</div>
{% endblock %}
HTML

echo "[OK] Đã ghi lại templates/settings.html (dùng chung base.html với Dashboard)."
