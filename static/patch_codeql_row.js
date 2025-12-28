(function () {
  function log(msg) {
    console.log('[CODEQL-PATCH]', msg);
  }

  function tryPatchOnce() {
    try {
      const cells = Array.from(document.querySelectorAll('td,div,span'));
      const banditCell = cells.find(
        el => el.textContent.trim().toUpperCase() === 'BANDIT'
      );

      if (!banditCell) {
        log('Chưa thấy ô BANDIT, sẽ thử lại...');
        return false;
      }

      let banditRow = banditCell.closest('tr');
      if (!banditRow) {
        banditRow = banditCell.parentElement;
      }
      if (!banditRow || !banditRow.parentElement) {
        log('Không xác định được row BANDIT.');
        return true; // dừng, tránh spam
      }

      // Clone row BANDIT -> CODEQL
      const newRow = banditRow.cloneNode(true);

      // Đổi text ô đầu tiên thành CODEQL
      const firstCell = newRow.querySelector('td,div,span');
      if (firstCell) {
        firstCell.textContent = 'CODEQL';
      }

      // Nếu là bảng <td>, chỉnh LEVEL & MODES cho đẹp
      const tds = newRow.querySelectorAll('td');
      if (tds.length >= 3) {
        tds[2].textContent = 'aggr';
      }
      if (tds.length >= 4) {
        tds[3].textContent = 'Offline, CI/CD';
      }

      banditRow.parentElement.insertBefore(newRow, banditRow.nextSibling);
      log('ĐÃ chèn thêm dòng CODEQL sau BANDIT.');
      return true;
    } catch (e) {
      console.error('[CODEQL-PATCH] Lỗi khi patch CODEQL row:', e);
      return true;
    }
  }

  function startPolling() {
    let attempts = 0;
    const maxAttempts = 30;
    const interval = setInterval(() => {
      attempts += 1;
      if (tryPatchOnce()) {
        clearInterval(interval);
        return;
      }
      if (attempts >= maxAttempts) {
        log('Hết số lần thử, dừng patch.');
        clearInterval(interval);
      }
    }, 1000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startPolling);
  } else {
    startPolling();
  }
})();


// PATCH_GLOBAL_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt ở SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/static/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Xóa riêng phần "8/7" trong header Crit/High
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var html = el.innerHTML || '';
          html = html.split('8/7').join('');      // bỏ mọi "8/7"
          html = html.replace(/\s{2,}/g, ' ');    // gom bớt khoảng trắng
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_GLOBAL_HIDE_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideStuff);
  } else {
    hideStuff();
  }

  var obs = new MutationObserver(function () {
    hideStuff();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
