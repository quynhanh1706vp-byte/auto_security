#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/settings.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

BKP="$TPL.bak_minimal_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BKP"
echo "[i] Backup settings.html -> $BKP"

cat > "$TPL" << 'HTML'
{% extends "base.html" %}

{% block title %}SECURITY BUNDLE – Settings{% endblock %}

{% block content %}
<div style="padding:32px;color:#e5f4ff;font-family:system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
  <h1 style="font-size:24px;margin:0 0 16px 0;">Settings</h1>

  <div style="margin-bottom:16px;font-size:13px;opacity:.8;">
    Config file:
    <code style="background:rgba(15,23,42,.9);padding:4px 8px;border-radius:4px;border:1px solid rgba(148,163,184,.6);">
      {{ cfg_path }}
    </code>
  </div>

  <h2 style="font-size:16px;margin:0 0 8px 0;">By tool / config</h2>

  <div style="border:1px solid rgba(148,163,184,.5);border-radius:8px;overflow:hidden;background:rgba(15,23,42,.9);">
    <table style="width:100%;border-collapse:collapse;font-size:13px;">
      <thead style="background:rgba(15,23,42,1);">
        <tr>
          <th style="text-align:left;padding:8px 12px;border-bottom:1px solid rgba(51,65,85,.9);">Tool</th>
          <th style="text-align:left;padding:8px 12px;border-bottom:1px solid rgba(51,65,85,.9);">Enabled</th>
          <th style="text-align:left;padding:8px 12px;border-bottom:1px solid rgba(51,65,85,.9);">Level</th>
          <th style="text-align:left;padding:8px 12px;border-bottom:1px solid rgba(51,65,85,.9);">Modes</th>
          <th style="text-align:left;padding:8px 12px;border-bottom:1px solid rgba(51,65,85,.9);">Notes</th>
        </tr>
      </thead>
      <tbody>
        {% for row in rows %}
        <tr style="border-top:1px solid rgba(30,41,59,.9);">
          <td style="padding:6px 12px;">{{ row.tool }}</td>
          <td style="padding:6px 12px;">
            {% if row.enabled %}
              <span style="padding:2px 8px;border-radius:999px;background:#16a34a;color:#020617;font-weight:500;">true</span>
            {% else %}
              <span style="padding:2px 8px;border-radius:999px;background:#4b5563;color:#e5e7eb;">false</span>
            {% endif %}
          </td>
          <td style="padding:6px 12px;">{{ row.level|upper }}</td>
          <td style="padding:6px 12px;">{{ row.modes }}</td>
          <td style="padding:6px 12px;">{{ row.notes }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
  </div>
</div>
{% endblock %}
HTML

echo "[OK] Đã ghi lại templates/settings.html (bản đơn giản, có header + bảng)."
