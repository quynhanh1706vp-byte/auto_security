(function () {
  function log(msg) {
    console.log('[ANYURL-RUN-UI]', msg);
  }

  // Tìm form ANY-URL
  function findAnyUrlForm() {
    var byId = document.getElementById('anyurl-form');
    if (byId) return byId;

    var byData = document.querySelector('form[data-anyurl-form="1"]');
    if (byData) return byData;

    var forms = Array.prototype.slice.call(document.querySelectorAll('form'));
    if (forms.length === 1) return forms[0];

    // nếu có nhiều form, ưu tiên form nào có text chứa "url" / "domain"
    for (var i = 0; i < forms.length; i++) {
      var f = forms[i];
      var txt = (f.textContent || '').toLowerCase();
      if (txt.indexOf('url') !== -1 || txt.indexOf('domain') !== -1) {
        return f;
      }
    }
    return null;
  }

  function submitAnyUrlForm() {
    var form = findAnyUrlForm();
    if (!form) {
      log('Không tìm thấy form ANY-URL để submit.');
      alert('Không tìm thấy form ANY-URL. Kiểm tra lại id="anyurl-form" hoặc data-anyurl-form="1".');
      return;
    }
    log('Submit form ANY-URL...');
    form.submit();
  }

  function bindButtons() {
    var btns = [];

    // 1) ưu tiên phần tử được gắn data-anyurl-run-ui="1" (nếu sau này bạn muốn gắn thẳng trong HTML)
    btns = btns.concat(Array.prototype.slice.call(
      document.querySelectorAll('[data-anyurl-run-ui="1"]')
    ));

    // 2) thêm các button / a có text chứa "Run UI"
    Array.prototype.slice.call(document.querySelectorAll('button, a'))
      .forEach(function (el) {
        var txt = (el.textContent || '').trim().toLowerCase();
        if (txt.indexOf('run ui') !== -1) {
          btns.push(el);
        }
      });

    // loại trùng
    btns = btns.filter(function (item, index) {
      return btns.indexOf(item) === index;
    });

    log('Tìm được ' + btns.length + ' nút Run UI.');

    btns.forEach(function (btn) {
      if (btn.dataset.anyurlRunUiBound === '1') return;
      btn.dataset.anyurlRunUiBound = '1';

      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        submitAnyUrlForm();
      });
    });
  }

  function init() {
    try {
      bindButtons();
    } catch (e) {
      console.error('[ANYURL-RUN-UI] Lỗi init:', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
