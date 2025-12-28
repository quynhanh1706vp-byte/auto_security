#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CFG="$ROOT/tool_config.json"
STATIC_CFG="$ROOT/static/tool_config.json"
JS="$ROOT/static/sb_fill_tools_from_config.js"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT  = $ROOT"
echo "[i] CFG   = $CFG"
echo "[i] OUT   = $STATIC_CFG"
echo "[i] JS    = $JS"
echo "[i] TPL   = $TPL"

# 1) Đồng bộ tool_config.json -> static/tool_config.json
if [ ! -f "$CFG" ]; then
  echo "[ERR] Không tìm thấy $CFG – kiểm tra lại."
  exit 1
fi

cp "$CFG" "$STATIC_CFG"
echo "[OK] Đã copy tool_config.json -> static/tool_config.json"

# 2) Tạo JS: đọc static/tool_config.json và fill bảng BY TOOL
cat > "$JS" <<'JS_EOF';
document.addEventListener('DOMContentLoaded', function () {
  const tbody = document.querySelector('.sb-card-tools table.sb-table tbody');
  if (!tbody) {
    console.warn('[SB-TOOLS] Không tìm thấy tbody BY TOOL.');
    return;
  }

  // Nếu đã điền rồi thì thôi
  if (tbody.getAttribute('data-sb-filled') === '1') {
    return;
  }

  fetch('/static/tool_config.json', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (data) {
      console.log('[SB-TOOLS] Đã load static/tool_config.json');

      if (!Array.isArray(data) || data.length === 0) {
        console.warn('[SB-TOOLS] tool_config.json không phải list hoặc rỗng.');
        return;
      }

      // Xoá dòng placeholder
      while (tbody.firstChild) {
        tbody.removeChild(tbody.firstChild);
      }

      data.forEach(function (t) {
        if (typeof t !== 'object' || !t) return;

        var name = t.tool || t.name || '';
        if (!name) return;

        var enabledRaw = String(t.enabled ?? '').toUpperCase();
        var enabled = (['1','TRUE','ON','YES'].indexOf(enabledRaw) !== -1) ? 'ON' : 'OFF';

        var level = t.level || t.profile || '';

        var modes = [];
        var offlineRaw = String(t.mode_offline ?? '1').toUpperCase();
        var onlineRaw  = String(t.mode_online  ?? '').toUpperCase();
        var cicdRaw    = String(t.mode_cicd    ?? '').toUpperCase();

        if (['0','FALSE','OFF','NO'].indexOf(offlineRaw) === -1) modes.push('Offline');
        if (['1','TRUE','ON','YES'].indexOf(onlineRaw) !== -1)   modes.push('Online');
        if (['1','TRUE','ON','YES'].indexOf(cicdRaw) !== -1)     modes.push('CI/CD');

        var tr = document.createElement('tr');

        function td(text, cls) {
          var cell = document.createElement('td');
          if (cls) cell.className = cls;
          cell.textContent = text;
          return cell;
        }

        tr.appendChild(td(name));
        tr.appendChild(td(enabled));
        tr.appendChild(td(level));
        tr.appendChild(td(modes.join(', ')));
        // COUNT tạm thời để '-' (sau này nếu muốn join summary_unified thì ta bơm tiếp)
        tr.appendChild(td('-', 'right'));

        tbody.appendChild(tr);
      });

      tbody.setAttribute('data-sb-filled', '1');
    })
    .catch(function (err) {
      console.warn('[SB-TOOLS] Lỗi load static/tool_config.json:', err);
    });
});
JS_EOF

echo "[OK] Đã ghi $JS"

# 3) Chèn script vào index.html nếu chưa có
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

if "sb_fill_tools_from_config.js" in data:
    print("[INFO] index.html đã include sb_fill_tools_from_config.js – bỏ qua.")
else:
    snippet = '  <script src="{{ url_for(\'static\', filename=\'sb_fill_tools_from_config.js\') }}"></script>\\n</body>'
    if "</body>" not in data:
        print("[ERR] Không thấy </body> trong index.html")
    else:
        data = data.replace("</body>", snippet)
        path.write_text(data, encoding="utf-8")
        print("[OK] Đã chèn script sb_fill_tools_from_config.js trước </body>.")
PY

echo "[DONE] patch_ui_tools_from_static.sh hoàn thành."
