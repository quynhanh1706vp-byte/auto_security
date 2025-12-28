(function () {
  function hideHint() {
    try {
      var text = 'Đang chờ chạy scan…';
      var nodes = Array.from(document.querySelectorAll('div,section,span'));

      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;

        var t = el.textContent.trim();
        // phải có đúng đoạn text
        if (t.indexOf(text) === -1) return;

        // CHỐT: chỉ ẩn những block text ngắn (<= 200 ký tự)
        // để tránh ẩn luôn nguyên layout / container lớn
        if (t.length > 200) return;

        el.style.display = 'none';
      });
    } catch (e) {
      console.warn('[SB-HIDE-RUN-HINT] error', e);
    }
  }

  document.addEventListener('DOMContentLoaded', hideHint);
})();