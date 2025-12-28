(function () {
  if (!window.VSP) window.VSP = {};

  function renderDatasource(rows) {
    var tbody = document.querySelector('#tbl-ds tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    (rows || []).forEach(function (r) {
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + (r.severity || '') + '</td>' +
        '<td>' + (r.tool || '') + '</td>' +
        '<td>' + (r.rule_id || '') + '</td>' +
        '<td>' + (r.file || '') + '</td>' +
        '<td>' + (r.line != null ? r.line : '') + '</td>' +
        '<td>' + (r.message || '') + '</td>' +
        '<td>' + ((r.cwe || r.cve || '') || '') + '</td>';
      tbody.appendChild(tr);
    });
  }

  function applyDsFilters(allRows) {
    var sevSel = document.getElementById('ds-sev');
    var toolSel = document.getElementById('ds-tool');
    var fileInput = document.getElementById('ds-file');
    var textInput = document.getElementById('ds-text');

    var sevVal = sevSel ? (sevSel.value || '') : '';
    var toolVal = toolSel ? (toolSel.value || '') : '';
    var fileVal = fileInput ? (fileInput.value || '').toLowerCase() : '';
    var textVal = textInput ? (textInput.value || '').toLowerCase() : '';

    var filtered = (allRows || []).filter(function (r) {
      var ok = true;
      if (sevVal && sevVal !== 'ALL') {
        ok = ok && ((r.severity || '') === sevVal);
      }
      if (toolVal && toolVal !== 'ALL') {
        ok = ok && ((r.tool || '') === toolVal);
      }
      if (fileVal) {
        ok = ok && ((r.file || '').toLowerCase().indexOf(fileVal) !== -1);
      }
      if (textVal) {
        var combo = ((r.message || '') + ' ' + (r.cwe || '') + ' ' + (r.cve || '') + ' ' + (r.rule_id || '')).toLowerCase();
        ok = ok && combo.indexOf(textVal) !== -1;
      }
      return ok;
    });

    // giới hạn khoảng 300 dòng cho UI
    renderDatasource(filtered.slice(0, 300));
  }

  function initDsFilters(allRows) {
    var sevSel = document.getElementById('ds-sev');
    var toolSel = document.getElementById('ds-tool');
    var fileInput = document.getElementById('ds-file');
    var textInput = document.getElementById('ds-text');
    var resetBtn = document.getElementById('ds-reset');

    if (sevSel) {
      var sevs = Array.from(new Set((allRows || []).map(r => r.severity).filter(Boolean)));
      sevSel.innerHTML = '<option value="ALL">All severity</option>' +
        sevs.map(s => `<option value="${s}">${s}</option>`).join('');
      sevSel.onchange = function () { applyDsFilters(allRows); };
    }

    if (toolSel) {
      var tools = Array.from(new Set((allRows || []).map(r => r.tool).filter(Boolean)));
      toolSel.innerHTML = '<option value="ALL">All tools</option>' +
        tools.map(t => `<option value="${t}">${t}</option>`).join('');
      toolSel.onchange = function () { applyDsFilters(allRows); };
    }

    if (fileInput) {
      fileInput.oninput = function () { applyDsFilters(allRows); };
    }

    if (textInput) {
      textInput.oninput = function () { applyDsFilters(allRows); };
    }

    if (resetBtn) {
      resetBtn.onclick = function () {
        if (sevSel) sevSel.value = 'ALL';
        if (toolSel) toolSel.value = 'ALL';
        if (fileInput) fileInput.value = '';
        if (textInput) textInput.value = '';
        applyDsFilters(allRows);
      };
    }
  }

  window.VSP.initDatasource = async function () {
    console.log('[VSP][UI] initDatasource');
    var rows = await window.VSP.API.getDatasource();
    if (!Array.isArray(rows)) {
      console.warn('[VSP][UI] datasource không phải array');
      rows = [];
    }
    initDsFilters(rows);
    applyDsFilters(rows);
  };
})();
