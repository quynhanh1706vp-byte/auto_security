/**
 * VSP 2025 – Vertical Tabs Runtime (commercial)
 *
 * Điều khiển 5 tab:
 *   Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
 *
 * Button:
 *   class: .vsp-nav-item hoặc .vsp-tab-btn
 *   attr:  data-tab-target="tab-dashboard" | "tab-runs" | ...
 *
 * Panel:
 *   class: .vsp-tab-panel
 *   id:    tab-dashboard | tab-runs | tab-datasource | tab-settings | tab-overrides
 */

(function () {
  var BUTTON_SELECTOR = ".vsp-nav-item, .vsp-tab-btn";
  var PANEL_SELECTOR  = ".vsp-tab-panel";

  function activateTab(targetId) {
    if (!targetId) return;

    var buttons = document.querySelectorAll(BUTTON_SELECTOR);
    var panels  = document.querySelectorAll(PANEL_SELECTOR);

    buttons.forEach(function (btn) {
      var t = btn.getAttribute("data-tab-target");
      var isActive = (t === targetId);
      btn.classList.toggle("is-active", isActive);
      btn.classList.toggle("active", isActive);
      btn.setAttribute("aria-selected", isActive ? "true" : "false");
    });

    panels.forEach(function (panel) {
      var isActive = (panel.id === targetId);
      panel.classList.toggle("is-active", isActive);
      panel.style.display = isActive ? "" : "none";
    });
  }

  function initTabs() {
    var buttons = document.querySelectorAll(BUTTON_SELECTOR);
    var panels  = document.querySelectorAll(PANEL_SELECTOR);
    if (!buttons.length || !panels.length) return;

    // Gắn handler click cho từng nút
    buttons.forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        var targetId = btn.getAttribute("data-tab-target");
        if (!targetId) return;
        activateTab(targetId);
      });
    });

    // Xác định tab mặc định: theo button đang .is-active, nếu không có thì lấy button đầu.
    var defaultId = null;
    buttons.forEach(function (btn) {
      if (btn.classList.contains("is-active") || btn.classList.contains("active")) {
        var t = btn.getAttribute("data-tab-target");
        if (t) defaultId = t;
      }
    });
    if (!defaultId && buttons[0]) {
      defaultId = buttons[0].getAttribute("data-tab-target");
    }

    // Ẩn/hiện panels theo default
    if (defaultId) {
      activateTab(defaultId);
    }
  }

  document.addEventListener("DOMContentLoaded", initTabs);
})();
