#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
JS="$ROOT/static/patch_runs_table_ui.js"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"
echo "[i] TPL  = $TPL"

########################################
# 1) Ghi file JS patch bảng RUN_*
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[RUNS-PATCH]', msg);
  }

  function norm(text) {
    return (text || '').replace(/\s+/g, ' ').trim();
  }

  function findRunsTable() {
    var tables = Array.from(document.querySelectorAll('table'));
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var headers = Array.from(t.querySelectorAll('thead th, thead td'));
      if (headers.some(function (h) {
        return /Lần quét/i.test(h.textContent || '');
      })) {
        return t;
      }
    }
    return null;
  }

  function applyStyles() {
    if (document.querySelector('style[data-runs-table-patch="1"]')) {
      return;
    }
    var css = `
      .runs-detail-cell a,
      .runs-detail-cell span,
      .runs-detail-cell {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 3px 10px;
        border-radius: 999px;
        border: 1px solid rgba(255, 255, 255, 0.25);
        font-size: 12px;
        font-weight: 500;
        white-space: nowrap;
        cursor: pointer;
        text-decoration: none;
      }
      .runs-detail-cell a:hover,
      .runs-detail-cell span:hover,
      .runs-detail-cell:hover {
        border-color: rgba(255, 255, 255, 0.5);
        background: rgba(255, 255, 255, 0.06);
      }
      .runs-no-data {
        opacity: 0.7;
        font-style: italic;
      }`;
    var style = document.createElement('style');
    style.setAttribute('data-runs-table-patch', '1');
    style.textContent = css;
    document.head.appendChild(style);
  }

  function patchTable() {
    var table = findRunsTable();
    if (!table) {
      log('Không tìm thấy bảng runs (có header "Lần quét").');
      return;
    }
    log('Đã tìm thấy bảng runs, bắt đầu patch.');

    if (table.tHead && table.tHead.rows.length > 0) {
      var headRow = table.tHead.rows[0];
      var cells = Array.from(headRow.cells);

      // Giữ "Tổng phát hiện" trên 1 dòng
      var totalCell = cells.find(function (c) {
        return norm(c.textContent) === 'Tổng phát hiện';
      });
      if (totalCell) {
        totalCell.style.whiteSpace = 'nowrap';
        totalCell.style.minWidth = '130px';
      }

      // Thêm header cho cột "Chi tiết"
      if (cells.length > 0) {
        var last = cells[cells.length - 1];
        if (!norm(last.textContent)) {
          last.textContent = 'Báo cáo / Chi tiết';
        }
      }
    }

    var body = table.tBodies[0];
    if (!body) {
      return;
    }

    Array.from(body.rows).forEach(function (row) {
      Array.from(row.cells).forEach(function (td) {
        var text = norm(td.textContent);

        // Style cho ô "Chi tiết"
        if (text === 'Chi tiết') {
          td.classList.add('runs-detail-cell');
        }
        // Thay "–" bằng text dễ hiểu hơn
        else if (text === '–' || text === '-') {
          td.textContent = 'Chưa có dữ liệu';
          td.classList.add('runs-no-data');
        }
      });
    });
  }

  function init() {
    try {
      applyStyles();
      patchTable();
    } catch (e) {
      console.error('[RUNS-PATCH] Lỗi:', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
JS
echo "[OK] Đã ghi $JS"

########################################
# 2) Chèn script vào templates/index.html
########################################
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
print("[PY] Đọc", path)
with open(path, "r", encoding="utf-8") as f:
    html = f.read()

marker = "patch_runs_table_ui.js"
if marker in html:
    print("[PY] index.html đã có patch_runs_table_ui.js, bỏ qua.")
    raise SystemExit(0)

needle = "</body>"
if needle not in html:
    print("[PY][ERR] Không tìm thấy </body> trong index.html")
    raise SystemExit(1)

snippet = """  <script src="{{ url_for('static', filename='patch_runs_table_ui.js') }}"></script>\n</body>"""

html = html.replace(needle, snippet)

with open(path, "w", encoding="utf-8") as f:
    f.write(html)

print("[PY] Đã chèn script patch_runs_table_ui.js trước </body>.")
PY

echo "[DONE] patch_runs_table_ui.sh hoàn thành."
