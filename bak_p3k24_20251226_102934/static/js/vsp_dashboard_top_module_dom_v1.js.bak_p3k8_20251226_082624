(function () {
  const LOG_PREFIX = "[VSP_TOP_MODULE_DOM]";

  function cleanupOnce() {
    try {
      const root = document.querySelector("#vsp-root") || document;
      if (!root) return;

      // Tìm phần tử có text "Top vulnerable module"
      const all = Array.from(root.querySelectorAll("*"));
      const labelEls = all.filter((el) => {
        if (!el || !el.textContent) return false;
        return el.textContent.trim() === "Top vulnerable module";
      });

      if (!labelEls.length) return;

      labelEls.forEach((labelEl) => {
        let valueEl = labelEl.nextElementSibling;
        if (!valueEl) {
          // thử tìm trong cùng block
          const parent = labelEl.parentElement;
          if (!parent) return;
          const candidates = Array.from(parent.children).filter((c) => c !== labelEl);
          valueEl = candidates[0] || null;
        }
        if (!valueEl) return;

        const raw = (valueEl.textContent || "").trim();
        if (!raw) return;

        let textOut = raw;

        // Nếu là JSON thì parse -> label/path/id
        try {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === "object") {
            textOut =
              parsed.label ||
              parsed.path ||
              parsed.id ||
              raw;
          }
        } catch (e) {
          // không phải JSON thì giữ nguyên
        }

        if (textOut && textOut.length > 80) {
          textOut = textOut.slice(0, 77) + "...";
        }

        if (textOut && textOut !== raw) {
          console.log(LOG_PREFIX, "Normalize top module:", raw, "=>", textOut);
          valueEl.textContent = textOut;
        }
      });
    } catch (err) {
      console.error(LOG_PREFIX, "cleanup error:", err);
    }
  }

  function startWatcher() {
    let tries = 0;
    const maxTries = 30; // ~15s nếu 500ms/lần

    const timer = setInterval(() => {
      tries += 1;
      cleanupOnce();
      if (tries >= maxTries) {
        clearInterval(timer);
      }
    }, 500);
  }

  // Chạy khi load xong
  if (document.readyState === "complete" || document.readyState === "interactive") {
    startWatcher();
  } else {
    window.addEventListener("DOMContentLoaded", startWatcher);
  }

  // Nếu dashboard có trigger event custom thì cũng bắt thêm
  window.addEventListener("vspDashboardV3Rendered", function () {
    console.log(LOG_PREFIX, "Received vspDashboardV3Rendered event");
    cleanupOnce();
  });
})();
