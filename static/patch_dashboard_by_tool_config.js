(function () {
  function log(msg) {
    console.log('[TOOLS-CONFIG]', msg);
  }

  function hidePlaceholder() {
    var nodes = document.querySelectorAll('td, div, p, span');
    nodes.forEach(function (n) {
      var txt = (n.textContent || '').trim();
      if (txt.indexOf('Chưa đọc được tool_config.json') !== -1) {
        n.style.display = 'none';
        log('Đã ẩn placeholder By tool/config.');
      }
    });
  }

  function guessToolsTable() {
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

      if (text.indexOf('tool') !== -1 &&
          text.indexOf('enabled') !== -1 &&
          text.indexOf('level') !== -1) {
        candidate = t;
        break;
      }
    }

    if (!candidate) {
      candidate = tables[tables.length - 1];
      log('Dùng bảng cuối làm BY TOOL / CONFIG (fallback).');
    } else {
      log('Đã tìm thấy bảng BY TOOL / CONFIG theo header.');
    }

    return candidate;
  }

  function renderTools(table, tools) {
    if (!table) return;

    var tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }

    tbody.innerHTML = '';

    if (!tools || !tools.length) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Không đọc được tool_config.json hoặc không có tool nào.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    tools.forEach(function (t) {
      var tr = document.createElement('tr');

      var tdTool = document.createElement('td');
      tdTool.textContent = t.tool || '';
      tr.appendChild(tdTool);

      var tdEnabled = document.createElement('td');
      tdEnabled.textContent = t.enabled ? 'ON' : 'OFF';
      tr.appendChild(tdEnabled);

      var tdLevel = document.createElement('td');
      tdLevel.textContent = t.level || '';
      tr.appendChild(tdLevel);

      var tdModes = document.createElement('td');
      tdModes.textContent = t.modes || '';
      tr.appendChild(tdModes);

      tbody.appendChild(tr);
    });
  }

  function init() {
    hidePlaceholder();

    var table = guessToolsTable();
    if (!table) return;

    log('Gọi /api/tools_by_config để fill BY TOOL / CONFIG.');

    fetch('/api/tools_by_config')
      .then(function (res) {
        if (!res.ok) {
          throw new Error('HTTP ' + res.status);
        }
        return res.json();
      })
      .then(function (data) {
        var tools = data && (data.tools || data.config || data);
        if (!Array.isArray(tools)) {
          log('Kết quả /api/tools_by_config không phải array / {tools:[...]}');
          return;
        }
        renderTools(table, tools);
      })
      .catch(function (err) {
        console.error('[TOOLS-CONFIG] Lỗi fetch /api/tools_by_config:', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
