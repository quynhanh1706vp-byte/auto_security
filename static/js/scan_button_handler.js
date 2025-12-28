(function () {
  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  function findScanButton() {
    // Ưu tiên id / class nếu có
    var btn = document.querySelector('#scan-btn, .scan-btn, button[data-role="run-scan"]');
    if (btn) return btn;

    // fallback: tìm button có text "Run scan"
    var buttons = Array.from(document.querySelectorAll('button'));
    for (var i = 0; i < buttons.length; i++) {
      var t = (buttons[i].textContent || '').trim().toLowerCase();
      if (t === 'run scan') return buttons[i];
    }
    return null;
  }

  function getSrcFolder() {
    var input =
      document.querySelector('input[name="src_folder"]') ||
      document.querySelector('#src-folder') ||
      document.querySelector('[data-role="src-folder"]');

    if (!input) return '';
    return (input.value || '').trim();
  }

  function wireScanButton() {
    var btn = findScanButton();
    if (!btn) {
      console.log('[UI] Không tìm thấy nút Run scan để gắn handler.');
      return;
    }

    console.log('[UI] Gắn handler cho nút Run scan.');

    btn.addEventListener('click', function (ev) {
      ev.preventDefault();

      var originalText = (btn.textContent || '').trim() || 'Run scan';
      var srcFolder = getSrcFolder();

      btn.disabled = true;
      btn.textContent = 'Running…';

      var payload = {
        src_folder: srcFolder,
        target_url: ''
      };

      fetch('/api/run_scan', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(payload)
      })
        .then(function (res) { return res.json(); })
        .then(function (data) {
          console.log('[UI] run_scan started:', data);

          btn.textContent = 'Running… (CLI)';

          setTimeout(function () {
            btn.disabled = false;
            btn.textContent = originalText;
          }, 2000);

          alert(
            'Đã trigger scan từ UI.\\n\\n' +
            'SRC: ' + (data.src_folder || '(mặc định)') + '\\n' +
            'Log: ' + (data.log_path || '') + '\\n\\n' +
            'Bạn xem tiến trình trong terminal hoặc tail log để theo dõi.'
          );
        })
        .catch(function (err) {
          console.error('[UI] Lỗi /api/run_scan:', err);
          alert('Lỗi gọi /api/run_scan: ' + err);
          btn.disabled = false;
          btn.textContent = originalText;
        });
    });
  }

  onReady(wireScanButton);
})();
