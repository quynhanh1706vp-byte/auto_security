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

cp "$TPL" "${TPL}.bak_table_style_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup settings.html."

python3 - << 'PY'
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

# 1) Thêm class sb-table-settings cho bảng Settings
if "sb-table-settings" not in data:
    before = "table.className = 'sb-table sb-table-compact';"
    after  = "table.className = 'sb-table sb-table-compact sb-table-settings';"
    if before in data:
        data = data.replace(before, after, 1)
        print("[OK] Thêm class sb-table-settings cho bảng Settings.")
    else:
        print("[WARN] Không tìm thấy dòng table.className để thêm class.")

# 2) Sửa cách build <tr> để dễ style + thêm tooltip cho Notes
old_block = """
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
"""
new_block = """
  cfg.forEach(t => {
    const tr = document.createElement('tr');
    const modes = Array.isArray(t.modes) ? t.modes.join(', ') : (t.modes || '');
    const note = t.note || t.desc || '';

    const tdTool = document.createElement('td');
    tdTool.textContent = t.tool || '';

    const tdEnabled = document.createElement('td');
    tdEnabled.textContent = String(t.enabled);

    const tdLevel = document.createElement('td');
    tdLevel.textContent = t.level || '';

    const tdModes = document.createElement('td');
    tdModes.textContent = modes || '-';

    const tdNote = document.createElement('td');
    tdNote.textContent = note;
    tdNote.title = note;

    tr.appendChild(tdTool);
    tr.appendChild(tdEnabled);
    tr.appendChild(tdLevel);
    tr.appendChild(tdModes);
    tr.appendChild(tdNote);

    tbody.appendChild(tr);
  });

  container.innerHTML = '';
  container.appendChild(table);
"""

if old_block in data:
    data = data.replace(old_block, new_block, 1)
    print("[OK] Đã thay block build <tr> bằng version DOM (có tooltip).")
else:
    print("[WARN] Không tìm thấy block cfg.forEach để thay.")

path.write_text(data, encoding="utf-8")
PY

echo "[DONE] patch_settings_table_style_v1.sh hoàn thành."
