// VSP_TABS_RUNTIME_V2_CLEAN – quản lý 5 tab chính, không gọi API
(function () {
  const LOG = "[VSP_TABS]";

  function activateTab(targetId) {
    const panes = document.querySelectorAll(".tab-pane");
    panes.forEach(p => {
      if (p.id === targetId) {
        p.classList.add("active");
      } else {
        p.classList.remove("active");
      }
    });

    const buttons = document.querySelectorAll("[data-tab-target]");
    buttons.forEach(b => {
      if (b.getAttribute("data-tab-target") === targetId) {
        b.classList.add("active");
      } else {
        b.classList.remove("active");
      }
    });

    console.log(LOG, "switch to", targetId);
  }

  document.addEventListener("DOMContentLoaded", function () {
    const buttons = document.querySelectorAll("[data-tab-target]");
    if (!buttons.length) {
      console.warn(LOG, "Không tìm thấy nút tab nào.");
      return;
    }

    buttons.forEach(btn => {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        const targetId = btn.getAttribute("data-tab-target");
        if (!targetId) return;
        activateTab(targetId);

        // Hook: khi chuyển tab, gọi loader nếu có
        if (targetId === "tab-runs" && window.vspLoadRunsTab) {
          window.vspLoadRunsTab();
        }
        if (targetId === "tab-data" && window.vspLoadDataSourceTab) {
          window.vspLoadDataSourceTab();
        }
      });
    });

    // đảm bảo có 1 tab active ban đầu
    const activePane = document.querySelector(".tab-pane.active");
    if (!activePane && buttons[0]) {
      const firstTarget = buttons[0].getAttribute("data-tab-target");
      if (firstTarget) {
        activateTab(firstTarget);
      }
    }

    console.log(LOG, "init done");
  });
})();
