#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TPL="templates/runs.html"
JS="static/patch_runs_table_v2.js"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"

########################################
# 1) JS: render bảng LAST RUNS & REPORTS
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[RUNS-TABLE]', msg);
  }

  async function fetchRuns() {
    try {
      const resp = await fetch('/api/runs');
      if (!resp.ok) {
        log('HTTP error ' + resp.status);
        return [];
      }
      const data = await resp.json();
      let items;
      if (Array.isArray(data)) items = data;
      else if (Array.isArray(data.items)) items = data.items;
      else items = [];

      // Chuẩn hoá field: run / time / total / crit / high
      return items.map(function (it) {
        const run =
          it.run || it.RUN || it.run_id || it.name || it.id || '';

        const time =
          it.time || it.datetime || it.mtime || it.created_at || '';

        const total =
          it.total || it.total_findings || it.count || it.num_findings || 0;

        let crit = it.crit || it.critical || 0;
        let high = it.high || 0;

        if (!crit && !high && typeof it.crit_high === 'string') {
          const parts = it.crit_high.split('/');
          if (parts.length === 2) {
            crit = parseInt(parts[0] || '0', 10) || 0;
            high = parseInt(parts[1] || '0', 10) || 0;
          }
        }

        return {
          run: run,
          time: time,
          total: total,
          crit: crit || 0,
          high: high || 0,
        };
      });
    } catch (e) {
      log('Error fetching runs: ' + e);
      return [];
    }
  }

  function findTableBody() {
    if (!window.location.pathname.startsWith('/runs')) return null;

    // Ưu tiên bảng có heading "LAST RUNS & REPORTS"
    const headings = Array.from(
      document.querySelectorAll('h1,h2,h3,h4,div,span')
    );
    const heading = headings.find(function (el) {
      return (
        el.textContent &&
        el.textContent.toUpperCase().includes('LAST RUNS & REPORTS')
      );
    });

    if (heading) {
      let container = heading.parentElement;
      for (let depth = 0; depth < 5 && container; depth++) {
        const tbl = container.querySelector('table');
        if (tbl) {
          return tbl.tBodies[0] || tbl.createTBody();
        }
        container = container.nextElementSibling || container.parentElement;
      }
    }

    // Fallback: lấy bảng đầu tiên
    const tbl = document.querySelector('table');
    if (!tbl) return null;
    return tbl.tBodies[0] || tbl.createTBody();
  }

  function render(rows) {
    const tbody = findTableBody();
    if (!tbody) {
      log('Không tìm thấy tbody cho bảng RUNS');
      return;
    }

    tbody.innerHTML = '';

    if (!rows.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 5;
      td.textContent = 'Chưa có RUN_* nào trong out/.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    rows.forEach(function (r) {
      const tr = document.createElement('tr');

      function cell(text) {
        const td = document.createElement('td');
        td.textContent = text || '';
        return td;
      }

      const critHighStr = String(r.crit || 0) + '/' + String(r.high || 0);

      tr.appendChild(cell(r.run || ''));
      tr.appendChild(cell(r.time || ''));
      tr.appendChild(cell(String(r.total || 0)));
      tr.appendChild(cell(critHighStr));

      // Cột Report: link HTML
      const tdRep = document.createElement('td');
      if (r.run) {
        const a = document.createElement('a');
        a.href = '/report/' + encodeURIComponent(r.run) + '/html';
        a.target = '_blank';
        a.textContent = 'HTML';
        tdRep.appendChild(a);
      } else {
        tdRep.textContent = '-';
      }
      tr.appendChild(tdRep);

      tbody.appendChild(tr);
    });
  }

  async function init() {
    if (!window.location.pathname.startsWith('/runs')) return;
    const rows = await fetchRuns();
    render(rows);
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(init, 0);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
JS

echo "[OK] Đã ghi $JS"

########################################
# 2) Chèn script vào runs.html
########################################
python3 - "$TPL" <<'PY'
import sys
from pathlib import Path

tpl_path = Path(sys.argv[1])
data = tpl_path.read_text(encoding="utf-8")

snippet = "  <script src=\"{{ url_for('static', filename='patch_runs_table_v2.js') }}\"></script>\\n</body>"

if "patch_runs_table_v2.js" in data:
    print("[INFO] runs.html đã có script patch_runs_table_v2.js, bỏ qua.")
else:
    if "</body>" not in data:
        raise SystemExit("[ERR] Không tìm thấy </body> trong runs.html")
    data = data.replace("</body>", snippet)
    tpl_path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script patch_runs_table_v2.js vào runs.html")
PY

echo "[DONE] patch_runs_table_v2.sh hoàn thành."
