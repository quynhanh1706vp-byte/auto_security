(function () {
  function log(msg) {
    console.log('[TREND-RUNS]', msg);
  }

  function guessTrendTable() {
    var tables = document.querySelectorAll('table');
    if (!tables.length) {
      log('Không tìm thấy table nào.');
      return null;
    }

    var candidate = null;

    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var head = t.querySelector('thead') || t.querySelector('tr');
      var text = (head && head.textContent || '').toLowerCase();

      if (text.indexOf('run') !== -1 &&
          text.indexOf('total') !== -1 &&
          (text.indexOf('crit') !== -1 || text.indexOf('crit/high') !== -1)) {
        candidate = t;
        break;
      }
    }

    if (!candidate) {
      candidate = tables[tables.length - 1];
      log('Dùng bảng cuối làm Trend – Last runs (fallback).');
    } else {
      log('Đã tìm thấy bảng Trend theo header.');
    }

    return candidate;
  }

  function renderTrend(table, runs) {
    if (!table) return;

    var tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }

    tbody.innerHTML = '';

    if (!runs || !runs.length) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Không tìm thấy RUN_* nào có report/summary_unified.json.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    runs.slice(0, 10).forEach(function (r) {
      var tr = document.createElement('tr');

      var tdRun = document.createElement('td');
      tdRun.textContent = r.run || '';
      tr.appendChild(tdRun);

      var tdTime = document.createElement('td');
      tdTime.textContent = r.time || '';
      tr.appendChild(tdTime);

      var tdTotal = document.createElement('td');
      tdTotal.textContent = (r.total != null ? r.total : '');
      tr.appendChild(tdTotal);

      var tdCH = document.createElement('td');
      var ch = '';
      if (r.critical != null || r.high != null) {
        ch = (r.critical || 0) + '/' + (r.high || 0);
      }
      tdCH.textContent = ch;
      tr.appendChild(tdCH);

      tbody.appendChild(tr);
    });
  }

  function init() {
    var table = guessTrendTable();
    if (!table) return;

    log('Gọi /api/runs để fill Trend – Last runs.');

    fetch('/api/runs')
      .then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then(function (data) {
        // /api/runs có thể trả array [] hoặc {runs:[...]}
        var runs = Array.isArray(data) ? data : (data.runs || []);
        if (!Array.isArray(runs)) {
          log('Kết quả /api/runs không phải array / {runs:[...]}');
          return;
        }
        renderTrend(table, runs);
      })
      .catch(function (err) {
        console.error('[TREND-RUNS] Lỗi fetch /api/runs:', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
