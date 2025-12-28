(function () {
  function hideRunHelp() {
    try {
      var texts = [
        'Khung này dùng để nhập và lưu lại cấu hình RUN trên UI',
        'Khung này dùng để nhập thông tin RUN và bấm Run scan',
        'Panel này chỉ dùng để ghi nhớ thông tin RUN trên UI',
        'Lưu cấu hình hiển thị'
      ];

      var nodes = Array.from(document.querySelectorAll('div, p, span, button, label'));

      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var t = el.textContent.replace(/\s+/g, ' ').trim();
        texts.forEach(function (needle) {
          if (!needle) return;
          if (t.indexOf(needle) !== -1) {
            // Ẩn đúng element chứa text đó (không đụng vào form RUN)
            el.style.display = 'none';
          }
        });
      });
    } catch (e) {
      console.warn('[SB-HIDE-RUN-HELP] error', e);
    }
  }

  document.addEventListener('DOMContentLoaded', hideRunHelp);
})();
