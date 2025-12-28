#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/sb_fill_runs_table_v3.js"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"

cat > "$JS" <<'JS'
document.addEventListener('DOMContentLoaded', function () {
  // Tìm tbody bảng RUN HISTORY
  var tbody =
    document.querySelector('.sb-card-runs table tbody') ||
    document.querySelector('.sb-runs-history table tbody') ||
    document.querySelector('#sb-runs-table tbody') ||
    document.querySelector('.sb-table-runs tbody');

  if (!tbody) {
    console.warn('[SB-RUNS] Không tìm thấy tbody bảng RUN HISTORY.');
    return;
  }

  fetch('/api/runs', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(async function (data) {
      if (!Array.isArray(data)) {
        console.warn('[SB-RUNS] /api/runs không trả list.');
        return;
      }

      var runs = data.slice();

      // Enrich: nếu total > 0 mà C/H/M/L = 0 hết thì cố gắng đọc summary_unified.json
      var enrichPromises = runs.map(function (run) {
        var total = Number(run.total || 0);
        var crit  = Number(run.crit ?? run.critical ?? 0);
        var high  = Number(run.high ?? 0);
        var med   = Number(run.medium ?? run.med ?? 0);
        var low   = Number(run.low ?? 0);

        var hasSeverity = (crit + high + med + low) > 0;

        // Lưu lại các field hiện có
        run.total  = total;
        run.crit   = crit;
        run.high   = high;
        run.medium = med;
        run.low    = low;

        if (!total || hasSeverity) {
          // Hoặc total=0, hoặc đã có C/H/M/L rồi -> không cần enrich
          return Promise.resolve();
        }

        var runId = run.run_id || run.run || run.id || '';
        if (!runId) return Promise.resolve();

        var url = '/out/' + encodeURIComponent(runId) + '/report/summary_unified.json';

        return fetch(url, { cache: 'no-store' })
          .then(function (res) {
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
          })
          .then(function (s) {
            run.total  = Number(s.total ?? s.total_findings ?? s.total_all ?? total);
            run.crit   = Number(s.critical ?? s.crit ?? 0);
            run.high   = Number(s.high ?? 0);
            run.medium = Number(s.medium ?? s.med ?? 0);
            run.low    = Number(s.low ?? 0);
          })
          .catch(function (err) {
            console.warn('[SB-RUNS] Không lấy được summary_unified cho', runId, err);
          });
      });

      await Promise.all(enrichPromises);

      // Render bảng
      tbody.innerHTML = '';

      runs.forEach(function (run) {
        var runId   = run.run_id || run.run || run.id || '';
        var time    = run.time || run.mtime || '';
        var total   = run.total  ?? 0;
        var crit    = run.crit   ?? run.critical ?? 0;
        var high    = run.high   ?? 0;
        var med     = run.medium ?? run.med ?? 0;
        var low     = run.low    ?? 0;
        var mode    = run.mode || '-';
        var profile = run.profile || '';

        var tr = document.createElement('tr');

        function td(text, cls) {
          var el = document.createElement('td');
          if (cls) el.className = cls;
          el.textContent = text;
          return el;
        }

        var tdRun = td(runId);
        tdRun.className = 'sb-col-run';
        tr.appendChild(tdRun);
        tr.appendChild(td(time));
        tr.appendChild(td(String(total), 'right'));
        tr.appendChild(td(String(crit) + '/' + String(high), 'right'));
        tr.appendChild(td(String(med), 'right'));
        tr.appendChild(td(String(low), 'right'));
        tr.appendChild(td(mode + (profile ? ' / ' + profile : '')));

        var tdReport = document.createElement('td');
        tdReport.className = 'right';
        var link = document.createElement('a');
        link.href = '/report/' + encodeURIComponent(runId) + '/html';
        link.textContent = 'Open report';
        tdReport.appendChild(link);
        tr.appendChild(tdReport);

        tbody.appendChild(tr);
      });
    })
    .catch(function (err) {
      console.warn('[SB-RUNS] Lỗi load /api/runs:', err);
    });
});
JS

echo "[DONE] patch_runs_table_v3_full.sh hoàn thành."
