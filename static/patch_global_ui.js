(function () {
  function log(msg) {
    console.log('[GLOBAL-UI]', msg);
  }

  function norm(t) {
    return (t || '').replace(/\s+/g, ' ').trim();
  }

  // ==== 1) Đổi label sidebar ====
  function patchSidebarLabels() {
    var map = {
      'Lần quét & Báo cáo': 'Run & Report',
      'Lần quét &amp; Báo cáo': 'Run & Report',
      'Cấu hình tool (JSON)': 'Settings',
      'Nguồn dữ liệu': 'Data Source'
    };

    var all = Array.from(document.body.querySelectorAll('*'));
    all.forEach(function (el) {
      if (!el.childNodes || el.childNodes.length !== 1) return;
      var node = el.childNodes[0];
      if (!node.nodeType || node.nodeType !== Node.TEXT_NODE) return;

      var textRaw = node.textContent || '';
      var text = norm(textRaw);
      if (!text) return;

      Object.keys(map).forEach(function (oldLabel) {
        if (text === norm(oldLabel)) {
          node.textContent = map[oldLabel];
        }
      });
    });
  }

  // ==== 2) Thêm PM HTML / PM PDF trên trang /runs ====

  function isRunsPage() {
    return /\/runs\/?$/.test(window.location.pathname);
  }

  function findRunsTable() {
    var tables = Array.from(document.querySelectorAll('table'));
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var headers = Array.from(t.querySelectorAll('thead th, thead td'));
      var hasRun = false;
      var hasDetail = false;
      headers.forEach(function (h) {
        var txt = norm(h.textContent || '').toUpperCase();
        if (txt === 'RUN') hasRun = true;
        if (txt === 'CHI TIẾT' || txt === 'CHI TIET') hasDetail = true;
      });
      if (hasRun && hasDetail) return t;
    }
    return null;
  }

  function patchRunsPage() {
    if (!isRunsPage()) return;

    var table = findRunsTable();
    if (!table) {
      log('Không tìm thấy bảng RUN (header RUN / CHI TIẾT).');
      return;
    }

    var headRow = table.tHead && table.tHead.rows[0];
    if (!headRow) return;

    var headCells = Array.from(headRow.cells);
    var idxRun = -1;
    var idxDetail = -1;
    headCells.forEach(function (c, i) {
      var txt = norm(c.textContent || '').toUpperCase();
      if (txt === 'RUN') idxRun = i;
      if (txt === 'CHI TIẾT' || txt === 'CHI TIET') idxDetail = i;
    });

    if (idxRun === -1 || idxDetail === -1) {
      log('Không xác định được cột RUN / CHI TIẾT.');
      return;
    }

    var body = table.tBodies[0];
    if (!body) return;

    var patched = 0;

    Array.from(body.rows).forEach(function (row) {
      var cells = Array.from(row.cells);
      if (cells.length <= Math.max(idxRun, idxDetail)) return;

      var runId = norm(cells[idxRun].textContent || '');
      if (!runId || !/^RUN_/.test(runId)) return;

      var cell = cells[idxDetail];
      if (!cell || cell.getAttribute('data-pm-links-added') === '1') return;

      cell.setAttribute('data-pm-links-added', '1');

      function makeLink(label, fmt) {
        var a = document.createElement('a');
        a.textContent = label;
        a.href = '/pm_report/' + encodeURIComponent(runId) + '/' + fmt;
        a.target = '_blank';
        a.style.marginLeft = '4px';
        return a;
      }

      // Giữ link "Xem chi tiết" cũ, thêm phần PM phía sau
      cell.appendChild(document.createTextNode(' | '));
      cell.appendChild(makeLink('PM HTML', 'html'));
      cell.appendChild(document.createTextNode(' / '));
      cell.appendChild(makeLink('PM PDF', 'pdf'));

      patched++;
    });

    log('Patched runs page – đã thêm PM cho ' + patched + ' dòng.');
  }

  function init() {
    try {
      patchSidebarLabels();
      patchRunsPage();
    } catch (e) {
      console.error('[GLOBAL-UI] Lỗi:', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
