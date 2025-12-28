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
