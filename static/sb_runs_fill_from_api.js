document.addEventListener('DOMContentLoaded', function () {
  // Tìm bảng RUNS & REPORTS (lấy table đầu tiên trong card)
  var card = document.querySelector('.sb-card, .sb-runs-card') || document;
  var table = card.querySelector('table');
  if (!table || !table.tBodies || !table.tBodies[0]) {
    console.warn('[SB-RUNS] Không tìm thấy bảng runs.');
    return;
  }
  var tbody = table.tBodies[0];

  // Hàm tiện ích tạo ô
  function td(text, cls) {
    var cell = document.createElement('td');
    if (cls) cell.className = cls;
    cell.textContent = text == null ? '' : String(text);
    return cell;
  }

  // Gọi API
  fetch('/api/runs', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (data) {
      console.log('[SB-RUNS] /api/runs OK', data);

      var list;
      if (Array.isArray(data)) {
        list = data;
      } else if (Array.isArray(data.runs)) {
        list = data.runs;
      } else if (Array.isArray(data.items)) {
        list = data.items;
      } else {
        list = [];
      }

      // Xoá placeholder cũ
      while (tbody.firstChild) tbody.removeChild(tbody.firstChild);

      if (!list.length) {
        var tr = document.createElement('tr');
        var cell = document.createElement('td');
        cell.colSpan = 7;
        cell.textContent = 'Chưa có RUN_* nào trong out/.';
        tr.appendChild(cell);
        tbody.appendChild(tr);
        return;
      }

      list.forEach(function (r) {
        if (!r || typeof r !== 'object') return;

        var runName = r.run || r.name || r.id || '';
        var time    = r.time || r.timestamp || r.mtime || '';
        var total   = r.total || r.total_findings || r.findings || 0;
        var crit    = r.crit  || r.critical || r.crit_count || 0;
        var high    = r.high  || r.high_count || 0;
        var ch      = r.ch    || r.crit_high || (crit + '/' + high);

        var reportUrl =
          r.report_html ||
          r.report_url  ||
          r.report ||
          '';

        var tr = document.createElement('tr');
        tr.appendChild(td(runName));
        tr.appendChild(td(time));
        tr.appendChild(td(total, 'right'));
        tr.appendChild(td(crit,  'right'));
        tr.appendChild(td(high,  'right'));
        tr.appendChild(td(ch,    'right'));

        var tdReport = document.createElement('td');
        tdReport.className = 'right';
        if (reportUrl) {
          var a = document.createElement('a');
          a.href = reportUrl;
          a.target = '_blank';
          a.textContent = 'HTML | PDF';
          tdReport.appendChild(a);
        } else {
          tdReport.textContent = '-';
        }
        tr.appendChild(tdReport);

        tbody.appendChild(tr);
      });
    })
    .catch(function (err) {
      console.warn('[SB-RUNS] Lỗi gọi /api/runs:', err);
    });
});
