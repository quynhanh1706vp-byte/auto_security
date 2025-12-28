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

cp "$TPL" "${TPL}.bak_frontend_v1_$(date +%Y%m%d_%H%M%S)" || true
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

      <div id="tool-config-table">
        <div class="sb-hint">
          Đang đọc <code>tool_config.json</code> từ RAW JSON phía dưới...
        </div>
      </div>
    </div>

    <!-- RAW JSON (DEBUG) -->
    <div class="sb-card">
      <div class="sb-section-title">RAW JSON (DEBUG)</div>
      <div class="sb-section-subtitle">
        For DevOps / kỹ thuật – đây là nội dung gốc của file <code>tool_config.json</code>.
      </div>
      <pre class="sb-json-block" id="tool-config-raw">{{ cfg_raw }}</pre>
    </div>

  </div>
</div>

<script>
// Frontend parser cho tool_config.json -> bảng BY TOOL / CONFIG
(function() {
  const pre = document.getElementById('tool-config-raw');
  const container = document.getElementById('tool-config-table');
  if (!pre || !container) return;

  const text = pre.textContent.trim();
  if (!text) {
    container.innerHTML = '<div class="sb-hint">No tool configuration loaded (RAW JSON trống).</div>';
    return;
  }

  function parseConfig(txt) {
    // 1) JSON chuẩn
    try {
      return JSON.parse(txt);
    } catch (e) {}

    // 2) JSON chuẩn nhưng file là list không bọc [] / dấu phẩy cuối
    try {
      return JSON.parse('[' + txt.replace(/,\\s*$/, '') + ']');
    } catch (e) {}

    // 3) Tự tách theo block { ... } bằng depth
    const items = [];
    let depth = 0;
    let buf = '';
    for (const ch of txt) {
      buf += ch;
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0 && buf.trim()) {
          let chunk = buf.trim();
          chunk = chunk.replace(/,\\s*$/, '');
          try {
            items.push(JSON.parse(chunk));
          } catch (e) {
            console.log('Chunk parse error:', e);
          }
          buf = '';
        }
      }
    }
    return items;
  }

  let cfg = parseConfig(text);
  if (cfg && cfg.tools && Array.isArray(cfg.tools)) {
    cfg = cfg.tools;
  }

  if (!Array.isArray(cfg) || cfg.length === 0) {
    container.innerHTML = '<div class="sb-hint">No tool configuration loaded or JSON parse error.</div>';
    return;
  }

  // Build bảng
  const table = document.createElement('table');
  table.className = 'sb-table sb-table-compact';
  table.innerHTML = `
    <thead>
      <tr>
        <th>Tool</th>
        <th>Enabled</th>
        <th>Level</th>
        <th>Modes</th>
        <th>Notes</th>
      </tr>
    </thead>
    <tbody></tbody>
  `;
  const tbody = table.querySelector('tbody');

  cfg.forEach(t => {
    const tr = document.createElement('tr');
    const modes = Array.isArray(t.modes) ? t.modes.join(', ') : (t.modes || '');
    const note = t.note || t.desc || '';
    tr.innerHTML = `
      <td>${t.tool || ''}</td>
      <td>${String(t.enabled)}</td>
      <td>${t.level || ''}</td>
      <td>${modes || '-'}</td>
      <td>${note}</td>
    `;
    tbody.appendChild(tr);
  });

  container.innerHTML = '';
  container.appendChild(table);
})();
</script>
"""

path.write_text(prefix + new_block, encoding="utf-8")
print("[OK] Đã ghi lại templates/settings.html (frontend JS parse tool_config.json).")
PY

echo "[DONE] patch_settings_frontend_table_v1.sh hoàn thành."
