/* ===== VSP RUN BAR VISIBILITY v1 ===== */
/*
  Mục tiêu:
  - Chỉ hiển thị RUN bar + config block khi đang ở tab Dashboard.
  - Các tab khác ẩn chúng đi.
*/

(function () {
  function updateVisibility() {
    var bar = document.getElementById('vsp-run-bar');
    var cfg = document.getElementById('vsp-settings-config-block');
    if (!bar && !cfg) return;

    // Tìm tab đang active (class .active)
    var activePane = null;
    var panes = document.querySelectorAll('.tab-pane');
    for (var i = 0; i < panes.length; i++) {
      if (panes[i].classList.contains('active')) {
        activePane = panes[i];
        break;
      }
    }

    var isDashboard = false;
    if (activePane && activePane.id === 'tab-dashboard') {
      isDashboard = true;
    }

    // RUN bar + config block chỉ hiện nếu tab-dashboard active
    if (bar) {
      bar.style.display = isDashboard ? '' : 'none';
    }
    if (cfg) {
      cfg.style.display = isDashboard ? '' : 'none';
    }
  }

  function init() {
    // Cập nhật ngay lần đầu
    updateVisibility();

    // Lắng nghe click trên menu bên trái (nav tab)
    var sidebar = document.querySelector('.vsp-sidebar, .sidebar, nav');
    if (sidebar) {
      sidebar.addEventListener('click', function () {
        setTimeout(updateVisibility, 50);
      });
    }

    // Fallback: poll nhẹ mỗi 500ms phòng khi tab switch bằng cách khác
    setInterval(updateVisibility, 500);
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(init, 0);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
