/**
 * VSP Dashboard Tables Live v2
 * - Đọc /api/vsp/datasource_v2?severity=HIGH&limit=10
 * - Đổ bảng "Top Risk Files" (file/path + CRIT/HIGH/MED/LOW)
 */
(function () {
  async function fetchTables() {
    try {
      const res = await fetch('/api/vsp/datasource_v2?severity=HIGH&limit=10');
      if (!res.ok) {
        console.warn('[VSP][TABLE] HTTP error', res.status);
        return null;
      }
      const data = await res.json();
      if (!data || data.ok === false) {
        console.warn('[VSP][TABLE] payload not ok', data);
        return null;
      }
      return data;
    } catch (e) {
      console.error('[VSP][TABLE] fetch error', e);
      return null;
    }
  }

  function findTopRiskFilesTable() {
    const tables = document.querySelectorAll('table');
    for (const tbl of tables) {
      const txt = (tbl.textContent || '').toUpperCase();
      if (txt.includes('TOP RISK FILES') ||
          txt.includes('RISK FILES') ||
          txt.includes('FILE / PATH') ||
          txt.includes('FILE/PATH')) {
        return tbl;
      }
    }
    return null;
  }

  function renderTopRiskFiles(topFiles) {
    const table = findTopRiskFilesTable();
    if (!table) {
      console.warn('[VSP][TABLE] Không tìm thấy bảng Top Risk Files.');
      return;
    }

    let tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }
    tbody.innerHTML = '';

    if (!Array.isArray(topFiles) || topFiles.length === 0) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 5;
      td.textContent = 'No data from latest FULL EXT run.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    topFiles.forEach(function (item) {
      if (!item || typeof item !== 'object') return;

      const path  = item.path || item.file || item.location || item.target || '(unknown)';
      const crit  = item.CRIT  ?? item.crit  ?? 0;
      const high  = item.HIGH  ?? item.high  ?? 0;
      const med   = item.MED   ?? item.MEDIUM ?? item.medium ?? 0;
      const low   = item.LOW   ?? item.low   ?? 0;

      const tr = document.createElement('tr');

      function tdCell(text) {
        const c = document.createElement('td');
        c.textContent = (typeof text === 'number') ? String(text) : (text || '');
        return c;
      }

      tr.appendChild(tdCell(path));
      tr.appendChild(tdCell(crit));
      tr.appendChild(tdCell(high));
      tr.appendChild(tdCell(med));
      tr.appendChild(tdCell(low));

      tbody.appendChild(tr);
    });

    console.log('[VSP][TABLE] Top Risk Files updated.');
  }

  async function initTables() {
    const data = await fetchTables();
    if (!data) return;
    renderTopRiskFiles(data.top_files || []);
  }

  document.addEventListener('DOMContentLoaded', function () {
    setTimeout(initTables, 900);
  });

  if (!window.VSP) window.VSP = {};
  if (!window.VSP.API) window.VSP.API = {};
  window.VSP.API.refreshTopRiskFiles = initTables;
})();
