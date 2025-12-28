(function () {
  function log(msg) {
    console.log('[TOP-RISKS]', msg);
  }

  async function fetchTopRisks() {
    try {
      const resp = await fetch('/api/top_risks_v3');
      if (!resp.ok) {
        log('HTTP error ' + resp.status);
        return [];
      }
      const data = await resp.json();
      if (!data) return [];
      if (Array.isArray(data)) return data;
      if (Array.isArray(data.items)) return data.items;
      return [];
    } catch (e) {
      log('Error fetching top risks: ' + e);
      return [];
    }
  }

  function findTableBody() {
    // Tìm heading chứa text "TOP RISK FINDINGS"
    const candidates = Array.from(
      document.querySelectorAll('h1,h2,h3,h4,h5,h6,div,span')
    );
    const heading = candidates.find(function (el) {
      return (
        el.textContent &&
        el.textContent.toUpperCase().includes('TOP RISK FINDINGS')
      );
    });

    if (!heading) {
      log('Không tìm thấy heading TOP RISK FINDINGS');
      return null;
    }

    // Đi xuống phía dưới để tìm bảng gần nhất
    let container = heading.parentElement;
    for (let depth = 0; depth < 5 && container; depth++) {
      const tbl = container.querySelector('table');
      if (tbl) {
        return tbl.tBodies[0] || tbl.createTBody();
      }
      container = container.nextElementSibling || container.parentElement;
    }

    log('Không tìm thấy bảng TOP RISK FINDINGS');
    return null;
  }

  function render(rows) {
    const tbody = findTableBody();
    if (!tbody) return;

    // Xoá placeholder cũ
    tbody.innerHTML = '';

    if (!rows.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Chưa có dữ liệu top risk.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    rows.forEach(function (r) {
      const tr = document.createElement('tr');

      function cell(text) {
        const td = document.createElement('td');
        td.textContent = text || '';
        return td;
      }

      tr.appendChild(cell(r.severity || ''));
      tr.appendChild(cell(r.tool || ''));
      tr.appendChild(cell(r.rule || ''));
      tr.appendChild(cell(r.location || ''));
      tbody.appendChild(tr);
    });
  }

  async function init() {
    // Chỉ chạy trên trang Dashboard (/ hoặc /dashboard)
    const path = window.location.pathname;
    if (!(path === '/' || path === '/dashboard' || path === '/index')) {
      return;
    }

    const rows = await fetchTopRisks();
    render(rows);
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(init, 0);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
