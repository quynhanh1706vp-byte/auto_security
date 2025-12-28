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

cp "$TPL" "${TPL}.bak_static_v2_$(date +%Y%m%d_%H%M%S)" || true
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
        <br>Source: <code>/static/last_tool_config.json</code>
      </div>

      <div id="tool-config-table">
        <div class="sb-hint">
          Đang đọc <code>/static/last_tool_config.json</code> ...
        </div>
      </div>
    </div>

    <!-- RAW JSON (DEBUG) -->
    <div class="sb-card">
      <div class="sb-section-title">RAW JSON (DEBUG)</div>
      <div class="sb-section-subtitle">
        Nội dung gốc đọc từ <code>/static/last_tool_config.json</code>.
      </div>
      <pre class="sb-json-block" id="tool-config-raw"></pre>
    </div>

  </div>
</div>

<script>
// Frontend parser cho /static/last_tool_config.json -> bảng BY TOOL / CONFIG
(function() {
  const container = document.getElementById('tool-config-table');
  const pre = document.getElementById('tool-config-raw');
  if (!container || !pre) return;

  function renderError(msg) {
    container.innerHTML = '<div class="sb-hint">' + msg + '</div>';
    pre.textContent = '';
  }

  function parseConfig(txt) {
    txt = txt.trim();
    if (!txt) return [];

    // 1) JSON chuẩn
    try {
      return JSON.parse(txt);
    } catch (e) {}

    // 2) JSON chuẩn nhưng là list không bọc [] / có dấu phẩy cuối
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

  fetch('/static/last_tool_config.json', {cache: 'no-store'})
    .then(resp => {
      if (!resp.ok) throw new Error('HTTP ' + resp.status);
      return resp.text();
    })
    .then(txt => {
      pre.textContent = txt || '';
      const raw = txt || '';
      let cfg = parseConfig(raw);

      if (cfg && cfg.tools && Array.isArray(cfg.tools)) {
        cfg = cfg.tools;
      }

      if (!Array.isArray(cfg) || cfg.length === 0) {
        renderError('No tool configuration loaded hoặc JSON không parse được.');
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
    })
    .catch(err => {
      console.log('tool_config fetch error:', err);
      renderError('Không đọc được /static/last_tool_config.json (' + err + ').');
    });
})();
</script>
"""

path.write_text(prefix + new_block, encoding="utf-8")
print("[OK] Đã ghi lại templates/settings.html (dùng /static/last_tool_config.json).")
PY

echo "[DONE] patch_settings_static_config_v2.sh hoàn thành."
