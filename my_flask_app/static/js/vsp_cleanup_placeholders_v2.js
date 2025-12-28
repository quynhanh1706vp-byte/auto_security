/**
 * [VSP][CLEANUP_V2]
 * Quét DOM nhiều lần để xoá các đoạn placeholder cũ:
 * - TAB 3 / TAB 4 / TAB 5
 */
(function () {
  function cleanOnce() {
    try {
      var patterns = [
        "TAB 3 -",
        "TAB 3 –",
        "TAB 4 -",
        "TAB 4 –",
        "TAB 5 -",
        "TAB 5 –",
      ];
      var nodes = document.querySelectorAll("body *");
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent.trim();
        if (!txt) return;
        for (var i = 0; i < patterns.length; i++) {
          if (txt.indexOf(patterns[i]) !== -1) {
            el.remove();
            break;
          }
        }
      });
    } catch (e) {
      console.warn("[VSP][CLEANUP_V2] Error:", e);
    }
  }

  function scheduleCleanup() {
    // chạy ngay + thêm vài lần nữa để bắt kịp nội dung inject chậm
    cleanOnce();
    var count = 0;
    var timer = setInterval(function () {
      cleanOnce();
      count += 1;
      if (count >= 6) {
        clearInterval(timer);
      }
    }, 500);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scheduleCleanup);
  } else {
    scheduleCleanup();
  }
})();
