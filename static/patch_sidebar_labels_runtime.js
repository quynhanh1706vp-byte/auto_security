(function () {
  function log(msg) {
    console.log('[SIDEBAR-PATCH]', msg);
  }

  function norm(t) {
    return (t || '').replace(/\s+/g, ' ').trim();
  }

  var map = {
    'Run & Report': 'Run & Report',
    'Cấu hình tool (JSON)': 'Settings',
    'Nguồn dữ liệu': 'Data Source'
  };

  function patchLabels() {
    var all = Array.from(document.body.querySelectorAll('*'));

    all.forEach(function (el) {
      if (!el.childNodes || el.childNodes.length !== 1) return;
      var node = el.childNodes[0];
      if (!node.nodeType || node.nodeType !== Node.TEXT_NODE) return;

      var text = norm(node.textContent || '');
      if (!text) return;

      Object.keys(map).forEach(function (oldLabel) {
        if (text === oldLabel) {
          node.textContent = map[oldLabel];
        }
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchLabels);
  } else {
    patchLabels();
  }
})();
