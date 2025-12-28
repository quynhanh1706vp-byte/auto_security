(function () {
  "use strict";

  const LOG_PREFIX = "[VSP_TABS]";

  function log() {
    // eslint-disable-next-line no-console
    console.log.apply(console, [LOG_PREFIX].concat(Array.from(arguments)));
  }

  function initTabs() {
    const buttons = document.querySelectorAll("[data-vsp-tab-target]");
    const panes = document.querySelectorAll(".vsp-tab-pane");

    if (!buttons.length || !panes.length) {
      log("No tab buttons or panes found – skip.");
      return;
    }

    function showTab(targetSelector) {
      if (!targetSelector) return;
      let found = false;

      panes.forEach((pane) => {
        if (pane.matches(targetSelector)) {
          pane.classList.add("vsp-tab-pane-active");
          pane.style.display = "";
          found = true;
        } else {
          pane.classList.remove("vsp-tab-pane-active");
          pane.style.display = "none";
        }
      });

      buttons.forEach((btn) => {
        const sel = btn.getAttribute("data-vsp-tab-target");
        if (sel === targetSelector) {
          btn.classList.add("vsp-tab-link-active");
        } else {
          btn.classList.remove("vsp-tab-link-active");
        }
      });

      if (!found) {
        log("No pane matched selector:", targetSelector);
      } else {
        log("Switched to tab:", targetSelector);
      }
    }

    buttons.forEach((btn) => {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        const sel = btn.getAttribute("data-vsp-tab-target");
        if (!sel) return;
        showTab(sel);
      });
    });

    let defaultSelector = null;

    if (window.location.hash && document.querySelector(window.location.hash)) {
      defaultSelector = window.location.hash;
    }
    if (!defaultSelector) {
      const defBtn = document.querySelector(
        "[data-vsp-tab-default='true'][data-vsp-tab-target]"
      );
      if (defBtn) {
        defaultSelector = defBtn.getAttribute("data-vsp-tab-target");
      }
    }
    if (!defaultSelector && buttons[0]) {
      defaultSelector = buttons[0].getAttribute("data-vsp-tab-target");
    }

    if (defaultSelector) {
      showTab(defaultSelector);
      log("Initialized, default tab =", defaultSelector);
    } else {
      log("Initialized without default tab.");
    }

    window.vspTabsShow = showTab;
  }

  document.addEventListener("DOMContentLoaded", initTabs);
})();
