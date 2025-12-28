(function () {
  function log(msg) {
    console.log('[RUN-SCAN]', msg);
  }

  function findRunScanButton() {
    var candidates = document.querySelectorAll(
      'button, a, input[type="button"], input[type="submit"]'
    );
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      var text = ((el.textContent || el.innerText || el.value || '') + '').trim().toLowerCase();
      if (text === 'run scan' || text.indexOf('run scan') !== -1) {
        return el;
      }
    }
    return null;
  }

  function findSrcInput() {
    // Ưu tiên placeholder có chữ Khach hoặc SRC/FOLDER
    var inputs = document.querySelectorAll('input[type="text"], input[type="search"]');
    var best = null;
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var ph = (el.placeholder || '').toLowerCase();
      if (ph.indexOf('khach') !== -1 || ph.indexOf('src') !== -1 || ph.indexOf('folder') !== -1) {
        return el;
      }
      // fallback: nếu có value /home/test/Data/Khach thì cũng dùng
      var v = (el.value || '').toLowerCase();
      if (v.indexOf('khach') !== -1) {
        best = el;
      }
    }
    return best;
  }

  function findTargetUrlInput() {
    var inputs = document.querySelectorAll('input[type="text"], input[type="url"]');
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var ph = (el.placeholder || '').toLowerCase();
      if (ph.indexOf('https://app.example.com') !== -1 ||
          ph.indexOf('target url') !== -1 ||
          ph.indexOf('domain') !== -1) {
        return el;
      }
    }
    return null;
  }

  function showStatus(msg, isError) {
    var id = 'run-scan-status';
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      el.style.marginTop = '8px';
      el.style.fontSize = '12px';
      el.style.opacity = '0.9';
      var dashboardTitle = document.querySelector('h2, h1');
      if (dashboardTitle && dashboardTitle.parentNode) {
        dashboardTitle.parentNode.appendChild(el);
      } else {
        document.body.appendChild(el);
      }
    }
    el.textContent = msg;
    el.style.color = isError ? '#ff6b6b' : '#a0ff9f';
  }

  function attach() {
    var btn = findRunScanButton();
    var srcInput = findSrcInput();

    if (!btn) {
      log('Không tìm thấy nút Run scan.');
      return;
    }
    if (!srcInput) {
      log('Không tìm thấy ô SRC FOLDER.');
    }

    var targetInput = findTargetUrlInput();

    log('Đã gắn handler cho nút Run scan.');

    btn.addEventListener('click', function (e) {
      try { e.preventDefault(); } catch (_) {}

      var src = srcInput ? (srcInput.value || '').trim() : '';
      var target = targetInput ? (targetInput.value || '').trim() : '';

      if (!src) {
        showStatus('Bạn chưa nhập SRC FOLDER.', true);
        alert('Bạn chưa nhập SRC FOLDER.');
        return;
      }

      // Normalize: nếu thiếu dấu / đầu, tự thêm
      if (src[0] !== '/' && !src.startsWith('~')) {
        src = '/' + src.replace(/^\/+/, '');
      }

      showStatus('Đang gửi yêu cầu scan cho: ' + src + ' ...', false);
      btn.disabled = true;

      fetch('/api/run_scan_simple', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          src_folder: src,
          target_url: target
        })
      })
        .then(function (res) { return res.json().catch(function(){ return {}; }); })
        .then(function (data) {
          btn.disabled = false;
          if (!data || data.ok === false) {
            var err = (data && data.error) || 'Không rõ lỗi.';
            showStatus('Run scan thất bại: ' + err, true);
            alert('Run scan thất bại: ' + err);
            return;
          }
          showStatus('Đã bắt đầu scan với SRC=' + data.src + '. Vui lòng đợi vài phút rồi F5 Dashboard.', false);
        })
        .catch(function (err) {
          btn.disabled = false;
          console.error('[RUN-SCAN] Lỗi gọi /api/run_scan_simple:', err);
          showStatus('Lỗi gọi /api/run_scan_simple. Xem console.', true);
        });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', attach);
  } else {
    attach();
  }
})();
