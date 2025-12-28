(function () {
  function switchTab(targetId) {
    // 1) Đổi active ở menu
    document.querySelectorAll(".vsp-menu-item").forEach(function (item) {
      var tabKey = item.getAttribute("data-tab");
      if (tabKey === targetId) {
        item.classList.add("active");
      } else {
        item.classList.remove("active");
      }
    });

    // 2) Ẩn/hiện nội dung tab
    document.querySelectorAll(".vsp-tab").forEach(function (panel) {
      if (panel.id === targetId) {
        panel.style.display = "block";
      } else {
        panel.style.display = "none";
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    // Gắn click handler
    document.querySelectorAll(".vsp-menu-item").forEach(function (item) {
      item.addEventListener("click", function () {
        var target = this.getAttribute("data-tab");
        if (!target) return;
        switchTab(target);
      });
    });

    // Mặc định mở Dashboard nếu có
    if (document.getElementById("tab-dashboard")) {
      switchTab("tab-dashboard");
    }
  });
})();
