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
      .runs-detail-cell {
        text-align: center;
        white-space: nowrap;
      }
      .runs-detail-cell a {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 3px 8px;
        border-radius: 999px;
        border: 1px solid rgba(255, 255, 255, 0.25);
        font-size: 12px;
        font-weight: 500;
        margin: 0 2px;
        text-decoration: none;
      }
      .runs-detail-cell a:hover {
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
      log('Không tìm thấy bảng runs (header "Lần quét").');
      return;
    }
    log('Đã tìm thấy bảng runs, patch PM report links.');

    // Header
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

      // Cột cuối: label rõ ràng
      if (cells.length > 0) {
        var last = cells[cells.length - 1];
        if (!norm(last.textContent)) {
          last.textContent = 'Báo cáo PM (HTML / PDF)';
        }
      }
    }

    var body = table.tBodies[0];
    if (!body) {
      return;
    }

    Array.from(body.rows).forEach(function (row) {
      var cells = Array.from(row.cells);
      if (cells.length === 0) return;

      var runId = norm(cells[0].textContent || '');

      // Check xem hàng này có dữ liệu hay không
      var hasData = cells.slice(1, -1).some(function (td) {
        var t = norm(td.textContent);
        return t && t !== '–' && t !== 'Chưa có dữ liệu';
      });

      // Xử lý từng cell
      cells.forEach(function (td, idx) {
        var text = norm(td.textContent);

        // Replace "–" cho các cột số liệu
        if (!hasData && text === '–' && idx !== cells.length - 1) {
          td.textContent = 'Chưa có dữ liệu';
          td.classList.add('runs-no-data');
        }

        // Cột cuối cùng: tạo 2 link HTML / PDF nếu có dữ liệu
        if (idx === cells.length - 1) {
          td.classList.add('runs-detail-cell');

          if (!runId || !hasData) {
            td.textContent = 'Không có báo cáo';
            td.classList.add('runs-no-data');
            return;
          }

          // Tạo link HTML & PDF
          var htmlLink = document.createElement('a');
          htmlLink.href = '/pm_report/' + encodeURIComponent(runId) + '/html';
          htmlLink.target = '_blank';
          htmlLink.textContent = 'HTML';

          var pdfLink = document.createElement('a');
          pdfLink.href = '/pm_report/' + encodeURIComponent(runId) + '/pdf';
          pdfLink.target = '_blank';
          pdfLink.textContent = 'PDF';

          td.innerHTML = '';
          td.appendChild(htmlLink);
          td.appendChild(pdfLink);
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
