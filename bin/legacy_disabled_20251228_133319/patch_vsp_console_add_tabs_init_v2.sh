#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_${TS}"

if grep -q "VSP_TABS_MAIN_INIT" "$JS"; then
  echo "[INFO] Tabs init đã tồn tại, không patch lại."
  exit 0
fi

cat >> "$JS" << 'JS_EOF'

// [VSP_TABS_MAIN_INIT]
(function () {
  "use strict";
  var LOG_PREFIX_TABS = "[VSP_TABS]";

  function logTabs() {
    if (typeof console !== "undefined" && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_PREFIX_TABS);
      console.log.apply(console, args);
    }
  }

  function normalizeLabel(text) {
    if (!text) return "";
    return text.replace(/\s+/g, " ").trim().toLowerCase();
  }

  function initTabs() {
    // Map label -> pane id
    var map = {
      "dashboard": "#vsp-tab-dashboard",
      "runs & reports": "#vsp-tab-runs",
      "data source": "#vsp-tab-datasource",
      "settings": "#vsp-tab-settings",
      "settings (profile / tools)": "#vsp-tab-settings",
      "rule overrides": "#vsp-tab-rules"
    };

    var buttons = [];
    var candidates = document.querySelectorAll("button, a, span");

    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      var label = normalizeLabel(el.textContent || el.innerText);
      if (map[label]) {
        el.setAttribute("data-vsp-tab-target", map[label]);
        el.classList.add("vsp-tab-link");
        buttons.push(el);
      }
    }

    var panes = document.querySelectorAll(".vsp-tab-pane");
    if (!buttons.length || !panes.length) {
      logTabs("No tab buttons or panes found – skip.", "buttons", buttons.length, "panes", panes.length);
      return;
    }

    function showTab(targetSelector) {
      if (!targetSelector) return;
      var found = false;

      for (var i = 0; i < panes.length; i++) {
        var pane = panes[i];
        if (pane.matches(targetSelector)) {
          pane.classList.add("vsp-tab-pane-active");
          pane.style.display = "";
          found = true;
        } else {
          pane.classList.remove("vsp-tab-pane-active");
          pane.style.display = "none";
        }
      }

      for (var j = 0; j < buttons.length; j++) {
        var btn = buttons[j];
        var sel = btn.getAttribute("data-vsp-tab-target");
        if (sel === targetSelector) {
          btn.classList.add("vsp-tab-link-active");
        } else {
          btn.classList.remove("vsp-tab-link-active");
        }
      }

      if (!found) {
        logTabs("No pane matched selector:", targetSelector);
      } else {
        logTabs("Switched to tab:", targetSelector);
      }
    }

    buttons.forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        var sel = btn.getAttribute("data-vsp-tab-target");
        if (!sel) return;
        showTab(sel);
      });
    });

    var defaultSelector = "#vsp-tab-dashboard";
    if (window.location.hash && document.querySelector(window.location.hash)) {
      defaultSelector = window.location.hash;
    }
    showTab(defaultSelector);
    logTabs("Initialized, default tab =", defaultSelector);

    // debug: vspTabsShow('#vsp-tab-runs')
    window.vspTabsShow = showTab;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initTabs);
  } else {
    initTabs();
  }
})();
JS_EOF

echo "[OK] Đã append tabs init vào $JS"
