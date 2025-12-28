#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/patch_runs_page_use_api.js"
TPL="$ROOT/templates/runs.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"
echo "[i] TPL  = $TPL"

cat > "$JS" <<'JS'
(function () {
  function log(msg) { console.log('[RUNS-PATCH]', msg); }
  function isRunsPage() { return location.pathname === '/runs'; }

  document.addEventListener('DOMContentLoaded', function () {
    if (!isRunsPage()) return;

    var table = document.querySelector('table');
    if (!table) {
      log('Không tìm thấy bảng RUNS.');
      return;
    }
    var tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }

    tbody.innerHTML = '<tr><td colspan="5">Đang load danh sách RUN_* từ /api/runs...</td></tr>';

    fetch('/api/runs')
      .then(function (r) { return r.json(); })
      .then(function (data) {
        log('data /api/runs = ' + JSON.stringify(data));
        var runs = Array.isArray(data) ? data : (data.runs || []);
        tbody.innerHTML = '';
        if (!runs.length) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 5;
          td.textContent = 'Không tìm thấy RUN_* nào trong out/.';
          tr.appendChild(td);
          tbody.appendChild(tr);
          return;
        }

        runs.forEach(function (rn) {
          var tr = document.createElement('tr');
          function td(txt) {
            var c = document.createElement('td');
            c.textContent = txt;
            return c;
          }

          var runId = rn.run || rn.id || rn.name || '';
          var crit  = rn.critical != null ? rn.critical : (rn.crit || 0);
          var high  = rn.high != null ? rn.high : 0;
          var total = rn.total != null ? rn.total : '';

          tr.appendChild(td(runId));          // RUN
          tr.appendChild(td(rn.time || ''));  // Time
          tr.appendChild(td(total));          // Total
          tr.appendChild(td(crit));           // Crit
          tr.appendChild(td(high));           // High

          tbody.appendChild(tr);
        });
      })
      .catch(function (err) {
        log('Lỗi load /api/runs: ' + err);
        tbody.innerHTML = '<tr><td colspan="5">Lỗi load /api/runs: ' + err + '</td></tr>';
      });
  });
})();
JS

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = "{{ url_for('static', filename='patch_runs_page_use_api.js') }}"
if snippet in data:
    print("[INFO] runs.html đã include patch_runs_page_use_api.js, bỏ qua.")
else:
    if '</body>' in data:
        data = data.replace('</body>', '  <script src="' + snippet + '"></script>\\n</body>')
    else:
        data = data.rstrip() + '\\n  <script src="' + snippet + '"></script>\\n'
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script patch_runs_page_use_api.js vào runs.html")
PY
