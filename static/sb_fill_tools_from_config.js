document.addEventListener('DOMContentLoaded', function () {
  const tbody = document.querySelector('.sb-card-tools table.sb-table tbody');
  if (!tbody) {
    console.warn('[SB-TOOLS] Không tìm thấy tbody BY TOOL.');
    return;
  }

  // Nếu đã điền rồi thì thôi
  if (tbody.getAttribute('data-sb-filled') === '1') {
    return;
  }

  fetch('/static/tool_config.json', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (data) {
      console.log('[SB-TOOLS] Đã load static/static/tool_config.json');

      if (!Array.isArray(data) || data.length === 0) {
        console.warn('[SB-TOOLS] tool_config.json không phải list hoặc rỗng.');
        return;
      }

      // Xoá dòng placeholder
      while (tbody.firstChild) {
        tbody.removeChild(tbody.firstChild);
      }

      data.forEach(function (t) {
        if (typeof t !== 'object' || !t) return;

        var name = t.tool || t.name || '';
        if (!name) return;

        var enabledRaw = String(t.enabled ?? '').toUpperCase();
        var enabled = (['1','TRUE','ON','YES'].indexOf(enabledRaw) !== -1) ? 'ON' : 'OFF';

        var level = t.level || t.profile || '';

        var modes = [];
        var offlineRaw = String(t.mode_offline ?? '1').toUpperCase();
        var onlineRaw  = String(t.mode_online  ?? '').toUpperCase();
        var cicdRaw    = String(t.mode_cicd    ?? '').toUpperCase();

        if (['0','FALSE','OFF','NO'].indexOf(offlineRaw) === -1) modes.push('Offline');
        if (['1','TRUE','ON','YES'].indexOf(onlineRaw) !== -1)   modes.push('Online');
        if (['1','TRUE','ON','YES'].indexOf(cicdRaw) !== -1)     modes.push('CI/CD');

        var tr = document.createElement('tr');

        function td(text, cls) {
          var cell = document.createElement('td');
          if (cls) cell.className = cls;
          cell.textContent = text;
          return cell;
        }

        tr.appendChild(td(name));
        tr.appendChild(td(enabled));
        tr.appendChild(td(level));
        tr.appendChild(td(modes.join(', ')));
        // COUNT tạm thời để '-' (sau này nếu muốn join summary_unified thì ta bơm tiếp)
        tr.appendChild(td('-', 'right'));

        tbody.appendChild(tr);
      });

      tbody.setAttribute('data-sb-filled', '1');
    })
    .catch(function (err) {
      console.warn('[SB-TOOLS] Lỗi load static/static/tool_config.json:', err);
    });
});
