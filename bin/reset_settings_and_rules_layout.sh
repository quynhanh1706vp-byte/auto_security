#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL_SETTINGS="$ROOT/templates/settings.html"
TPL_RULES="$ROOT/templates/rule_overrides.html"

echo "[i] ROOT = $ROOT"

# Backup nếu tồn tại
for f in "$TPL_SETTINGS" "$TPL_RULES"; do
  if [ -f "$f" ]; then
    cp "$f" "${f}.bak_reset_$(date +%Y%m%d_%H%M%S)"
    echo "[OK] Backup $f"
  fi
done

# === settings.html – layout giống Dashboard, 1 card bảng tool config ===
cat > "$TPL_SETTINGS" <<'HTML'
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

  <div class="sb-card">
    <div class="sb-card-header">
      <div class="sb-card-title">By tool / config</div>
      <div class="sb-card-subtitle">
        Bảng cấu hình từng tool (Enabled, Level, Modes, Notes).
      </div>
    </div>

    <div class="sb-table-wrapper">
      <table class="sb-table" id="sb-settings-table">
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
          {# Sau này JS bind dữ liệu từ tool_config.json vào đây #}
        </tbody>
      </table>
    </div>

    <div style="margin-top:12px;font-size:13px;opacity:.8">
      Cấu hình thực tế đọc từ <code>tool_config.json</code>. UI chỉ hiển thị ở đây để review nhanh.
    </div>
  </div>
</div>
{% endblock %}
HTML

echo "[OK] Đã ghi lại templates/settings.html"

# === rule_overrides.html – layout giống Dashboard, 2 card: overview + bảng overrides ===
cat > "$TPL_RULES" <<'HTML'
{% extends "base.html" %}

{% block title %}SECURITY_BUNDLE – Rule overrides{% endblock %}

{% block content %}
<div class="sb-main sb-page-rules">
  <div class="sb-main-header">
    <div class="sb-main-title">Rule overrides</div>
    <div class="sb-main-subtitle">
      Tùy chỉnh rule / ngoại lệ cho findings từ các tool.
    </div>
  </div>

  <div class="sb-grid sb-grid-2">
    <!-- Card trái: mô tả & nguồn dữ liệu override -->
    <div class="sb-card">
      <div class="sb-card-header">
        <div class="sb-card-title">Overview</div>
        <div class="sb-card-subtitle">
          Nơi định nghĩa override (bỏ qua, hạ mức, note thêm) cho từng rule.
        </div>
      </div>

      <div style="font-size:13px;line-height:1.6;opacity:.9">
        <ul style="padding-left:18px;margin:0">
          <li>Map theo <b>Tool</b> + <b>Rule / ID</b> (hoặc pattern theo prefix).</li>
          <li>Có thể set <b>Action</b>: keep, mute, lower severity, custom tag.</li>
          <li>File override (JSON/YAML) được đọc ở bước unify findings.</li>
        </ul>

        <div style="margin-top:14px">
          File override hiện tại:
          <code>rules_overrides.json</code> (hoặc tương đương – cấu hình trong backend).
        </div>
      </div>
    </div>

    <!-- Card phải: bảng Rule overrides -->
    <div class="sb-card">
      <div class="sb-card-header">
        <div class="sb-card-title">Rule overrides table</div>
        <div class="sb-card-subtitle">
          Preview các override đã load (chỉ hiển thị, không edit trực tiếp).
        </div>
      </div>

      <div class="sb-table-wrapper">
        <table class="sb-table" id="sb-rule-overrides-table">
          <thead>
            <tr>
              <th>SEVERITY</th>
              <th>RULE / ID</th>
              <th>TOOL</th>
              <th>ACTION</th>
              <th>NOTES</th>
            </tr>
          </thead>
          <tbody id="sb-rule-overrides-body">
            {# Sau này JS bind dữ liệu override vào đây #}
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
{% endblock %}
HTML

echo "[OK] Đã ghi lại templates/rule_overrides.html"

