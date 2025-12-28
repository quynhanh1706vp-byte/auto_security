#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/settings.html"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

cp "$TPL" "${TPL}.bak_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup settings.html."

python3 - << 'PY'
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

marker = "<!-- Main content -->"
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy marker '<!-- Main content -->' trong settings.html")
    raise SystemExit(1)

prefix = data[:idx]

new_block = """<!-- Main content -->
<div class="sb-main">
  <div class="sb-main-header">
    <div class="sb-main-title">Settings</div>
    <div class="sb-main-subtitle">
      Tool configuration loaded from <code>tool_config.json</code>.
    </div>
    <div class="sb-pill-top-right">
      Config file: {{ cfg_path }}
    </div>
  </div>

  <div class="sb-main-content">

    <!-- BY TOOL / CONFIG -->
    <div class="sb-card">
      <div class="sb-section-title">BY TOOL / CONFIG</div>
      <div class="sb-section-subtitle">
        ON/OFF, level &amp; modes per tool. Những giá trị này sẽ được dùng cho CLI / CI/CD.
      </div>

      {% set rows_ = cfg_rows or table_rows or rows %}
      {% if rows_ and rows_|length > 0 %}
        <div class="sb-table-wrapper">
          <table class="sb-table sb-table-compact">
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
              {% for t in rows_ %}
              <tr>
                <td>{{ t.tool }}</td>
                <td>{{ t.enabled }}</td>
                <td>{{ t.level }}</td>
                <td>
                  {% if t.modes %}
                    {{ t.modes|join(", ") }}
                  {% else %}
                    -
                  {% endif %}
                </td>
                <td>{{ t.note or t.desc or "" }}</td>
              </tr>
              {% endfor %}
            </tbody>
          </table>
        </div>
      {% else %}
        <div class="sb-hint">
          No tool configuration loaded or <code>tool_config.json</code> is empty.
        </div>
      {% endif %}
    </div>

    <!-- RAW JSON (DEBUG) -->
    <div class="sb-card">
      <div class="sb-section-title">RAW JSON (DEBUG)</div>
      <div class="sb-section-subtitle">
        For DevOps / kỹ thuật – đây là nội dung gốc của file <code>tool_config.json</code>.
      </div>
      <pre class="sb-json-block">{{ cfg_raw }}</pre>
    </div>

  </div>
</div>
"""

path.write_text(prefix + new_block, encoding="utf-8")
print("[OK] Đã ghi lại templates/settings.html (BY TOOL table + RAW JSON).")
PY

echo "[DONE] patch_settings_template_table_v2.sh hoàn thành."
