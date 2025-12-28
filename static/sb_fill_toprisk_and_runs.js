document.addEventListener('DOMContentLoaded', function () {
  const tbRisk = document.querySelector('.sb-table-toprisk tbody');
  const tbRuns = document.querySelector('.sb-table-runs tbody');

  if (!tbRisk && !tbRuns) {
    console.warn('[SB-SUMMARY] Không tìm thấy tbody top_risks / runs.');
    return;
  }

  fetch('/static/summary_unified_latest.json', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (summary) {
      console.log('[SB-SUMMARY] Đã load summary_unified_latest.json');

      // --------- TOP RISK FINDINGS ----------
      if (tbRisk) {
        var top = summary.top_risks || summary.topRisks ||
                  summary.top_findings || summary.topFindings || [];

        // clear placeholder
        while (tbRisk.firstChild) tbRisk.removeChild(tbRisk.firstChild);

        if (!Array.isArray(top) || top.length === 0) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 4;
          td.className = 'muted';
          td.textContent = 'Chưa có dữ liệu top risk.';
          tr.appendChild(td);
          tbRisk.appendChild(tr);
        } else {
          top.forEach(function (f) {
            if (typeof f !== 'object' || !f) return;
            var tr = document.createElement('tr');

            function td(text) {
              var cell = document.createElement('td');
              cell.textContent = text || '';
              return cell;
            }

            var sev  = f.severity || f.SEVERITY || '';
            var tool = f.tool || f.scanner || f.SCAN_TOOL || '';
            var rule = f.rule || f.id || f.rule_id || '';
            var loc  = f.location || f.file || f.path || '';

            tr.appendChild(td(sev));
            tr.appendChild(td(tool));
            tr.appendChild(td(rule));
            tr.appendChild(td(loc));

            tbRisk.appendChild(tr);
          });
        }
      }

      // --------- TREND – LAST RUNS ----------
      if (tbRuns) {
        var runs = summary.runs || summary.trend_last_runs ||
                   summary.trendRuns || [];

        while (tbRuns.firstChild) tbRuns.removeChild(tbRuns.firstChild);

        if (!Array.isArray(runs) || runs.length === 0) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 4;
          td.className = 'muted';
          td.textContent = 'Chưa có lịch sử RUN.';
          tr.appendChild(td);
          tbRuns.appendChild(tr);
        } else {
          runs.forEach(function (r) {
            if (typeof r !== 'object' || !r) return;
            var tr = document.createElement('tr');

            function td(text, cls) {
              var cell = document.createElement('td');
              if (cls) cell.className = cls;
              cell.textContent = text || '';
              return cell;
            }

            var name = r.name || r.run || r.id || '';
            var time = r.time || r.timestamp || '';
            var total = r.total || r.findings || 0;
            var ch = r.crit_high || r.critHigh || r.crit_high_str || '';

            tr.appendChild(td(name));
            tr.appendChild(td(time));
            tr.appendChild(td(String(total), 'right'));
            tr.appendChild(td(ch, 'right'));

            tbRuns.appendChild(tr);
          });
        }
      }
    })
    .catch(function (err) {
      console.warn('[SB-SUMMARY] Lỗi load summary_unified_latest.json:', err);
    });
});
