#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

cat > templates/settings.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>SECURITY BUNDLE – Settings</title>
  <link rel="stylesheet" href="/static/css/security_resilient.css" />
</head>
<body class="sb-body">
<div class="sb-layout">
  <!-- Sidebar -->
  <div class="sb-sidebar">
    <div class="sb-logo">SECURITY<br>BUNDLE</div>
    <div class="sb-nav">
      <div class="nav-item"><a href="/">Dashboard</a></div>
      <div class="nav-item"><a href="/runs">Runs &amp; Reports</a></div>
      <div class="nav-item nav-item-active"><a href="/settings">Settings</a></div>
      <div class="nav-item"><a href="/datasource">Data Source</a></div>
    </div>
  </div>

  <!-- Main content -->
  <div class="sb-main">
    <div class="sb-main-header">
      <div class="sb-main-title">Settings</div>
      <div class="sb-main-subtitle">Tool configuration loaded from <code>tool_config.json</code>.</div>
      <div class="sb-pill-top-right">
        Config file: {{ cfg_path }}
      </div>
    </div>

    <div class="sb-main-grid sb-main-grid-2">
      <!-- LEFT: editable table -->
      <div class="sb-card">
        <div class="sb-card-title">BY TOOL / CONFIG</div>
        <div class="sb-card-subtitle">
          ON/OFF, level &amp; modes per tool. Những giá trị này sẽ được dùng cho CLI / CI/CD.
        </div>

        <form method="post">
          <table class="sb-table sb-table-tight">
            <thead>
              <tr>
                <th style="width:160px;">Tool</th>
                <th style="width:80px;">Enabled</th>
                <th style="width:100px;">Level</th>
                <th style="width:220px;">Modes</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              {% if tools %}
                {% for t in tools %}
                <tr>
                  <td>{{ t.tool or t["tool"] }}</td>
                  <td>
                    {% set enabled = t.enabled if t.enabled is not none else t.get("enabled", True) %}
                    <select name="tool-{{ loop.index0 }}-enabled" class="sb-input sb-input-xs">
                      <option value="ON"  {% if enabled %}selected{% endif %}>ON</option>
                      <option value="OFF" {% if not enabled %}selected{% endif %}>OFF</option>
                    </select>
                  </td>
                  <td>
                    <input
                      type="text"
                      name="tool-{{ loop.index0 }}-level"
                      value="{{ t.level or t.get('level','') }}"
                      class="sb-input sb-input-xs"
                      placeholder="fast / aggr / ...">
                  </td>
                  <td>
                    <input
                      type="text"
                      name="tool-{{ loop.index0 }}-modes"
                      value="{% if t.modes is defined %}{{ ', '.join(t.modes) }}{% else %}{{ ', '.join(t.get('modes', [])) }}{% endif %}"
                      class="sb-input sb-input-xs"
                      placeholder="Offline, Online, CI/CD">
                  </td>
                  <td class="sb-col-notes">
                    {{ t.note or t.get("note","") }}
                  </td>
                </tr>
                {% endfor %}
              {% else %}
                <tr>
                  <td colspan="5">No tool configuration loaded.</td>
                </tr>
              {% endif %}
            </tbody>
          </table>

          <div class="sb-form-actions">
            <button type="submit" class="sb-btn-primary">Save changes</button>
            <span class="sb-form-hint">
              Thay đổi sẽ được ghi trực tiếp vào <code>tool_config.json</code>.
            </span>
          </div>
        </form>
      </div>

      <!-- RIGHT: raw JSON -->
      <div class="sb-card">
        <div class="sb-card-title">RAW JSON (DEBUG)</div>
        <div class="sb-card-subtitle">
          For DevOps / kỹ thuật – đây là nội dung gốc của <code>tool_config.json</code>.
        </div>
        <pre class="sb-pre-json">{{ raw_json }}</pre>
      </div>
    </div>
  </div>
</div>
</body>
</html>
HTML
