document.addEventListener('DOMContentLoaded', () => {
  const tbody = document.querySelector('#runs-tbody');
  if (!tbody) return;

  fetch('/api/runs_table')
    .then(r => r.json())
    .then(rows => {
      tbody.innerHTML = '';
      if (!rows || !rows.length) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = 7;
        td.textContent = 'Chưa có RUN nào trong out/. Hãy chạy scan trước.';
        td.style.textAlign = 'center';
        td.style.opacity = '0.75';
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
      }
      for (const r of rows) {
        const tr = document.createElement('tr');

        const tdRun = document.createElement('td');
        tdRun.textContent = r.run;
        tr.appendChild(tdRun);

        const tdTime = document.createElement('td');
        tdTime.textContent = r.time || '-';
        tr.appendChild(tdTime);

        const tdSrc = document.createElement('td');
        tdSrc.textContent = r.src || '-';
        tr.appendChild(tdSrc);

        const tdTotal = document.createElement('td');
        tdTotal.textContent = r.total ?? '-';
        tr.appendChild(tdTotal);

        const tdCritHigh = document.createElement('td');
        tdCritHigh.textContent = (r.crit ?? 0) + ' / ' + (r.high ?? 0);
        tr.appendChild(tdCritHigh);

        const tdMode = document.createElement('td');
        tdMode.textContent = r.mode || '-';
        tr.appendChild(tdMode);

        const tdReports = document.createElement('td');
        tdReports.innerHTML =
          '<a href="/pm_report/' + encodeURIComponent(r.run) + '/html" target="_blank">HTML</a>' +
          ' \u00b7 ' +
          '<a href="/pm_report/' + encodeURIComponent(r.run) + '/pdf" target="_blank">PDF</a>';
        tr.appendChild(tdReports);

        tbody.appendChild(tr);
      }
    })
    .catch(err => {
      console.error('ERR runs_table_fill:', err);
    });
});
