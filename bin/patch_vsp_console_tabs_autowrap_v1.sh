#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_autowrap_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_autowrap_${TS}"

cat >> "$JS" << 'JS_EOF'

// [VSP_TABS_AUTOWRAP_V1]
(function () {
  "use strict";

  var LOG_WRAP = "[VSP_TABS_WRAP]";
  var LOG_TABS2 = "[VSP_TABS2]";

  function logWrap() {
    if (typeof console !== "undefined" && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_WRAP);
      console.log.apply(console, args);
    }
  }

  function logTabs2() {
    if (typeof console !== "undefined" && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG_TABS2);
      console.log.apply(console, args);
    }
  }

  function ensurePanes() {
    // Nếu đã có rồi thì thôi
    var existing = document.querySelectorAll(".vsp-tab-pane");
    if (existing.length) {
      logWrap("Found existing panes, skip autowrap. count =", existing.length);
      return;
    }

    var main = document.querySelector("main");
    if (!main) {
      logWrap("No <main> found – cannot autowrap.");
      return;
    }

    // Bọc main vào pane Dashboard
    var wrap = document.createElement("div");
    wrap.id = "vsp-tab-dashboard";
    wrap.className = "vsp-tab-pane vsp-tab-pane-active";

    main.parentNode.insertBefore(wrap, main);
    wrap.appendChild(main);

    // Tạo thêm 4 pane rỗng
    function addPane(id, text) {
      var pane = document.createElement("div");
      pane.id = id;
      pane.className = "vsp-tab-pane";
      var card = document.createElement("div");
      card.className = "vsp-card";
      var body = document.createElement("div");
      body.className = "vsp-card-body";
      body.textContent = text;
      card.appendChild(body);
      pane.appendChild(card);
      wrap.parentNode.insertBefore(pane, wrap.nextSibling);
      wrap = pane; // để nó nối tiếp nhau
    }

    addPane("vsp-tab-runs", "Runs & Reports tab V1 – content TODO.");
    addPane("vsp-tab-datasource", "Data Source tab V1 – content TODO.");
    addPane("vsp-tab-settings", "Settings tab V1 – content TODO.");
    addPane("vsp-tab-rules", "Rule Overrides tab V1 – content TODO.");

    var after = document.querySelectorAll(".vsp-tab-pane").length;
    logWrap("Created tab panes:", after);
  }

  function initTabs2() {
    var panes = document.querySelectorAll(".vsp-tab-pane");
    if (!panes.length) {
      logTabs2("No panes after autowrap – skip.");
      return;
    }

    var buttons = document.querySelectorAll("[data-vsp-tab-target]");
    if (!buttons.length) {
      logTabs2("No buttons with data-vsp-tab-target – skip.");
      return;
    }

    function showTab(targetSelector) {
      if (!targetSelector) return;
      var found = false;

      panes.forEach(function (pane) {
        if (pane.matches(targetSelector)) {
          pane.classList.add("vsp-tab-pane-active");
          pane.style.display = "";
          found = true;
        } else {
          pane.classList.remove("vsp-tab-pane-active");
          pane.style.display = "none";
        }
      });

      buttons.forEach(function (btn) {
        var sel = btn.getAttribute("data-vsp-tab-target");
        if (sel === targetSelector) {
          btn.classList.add("vsp-tab-link-active");
        } else {
          btn.classList.remove("vsp-tab-link-active");
        }
      });

      if (!found) {
        logTabs2("No pane matched selector:", targetSelector);
      } else {
        logTabs2("Switched to tab:", targetSelector);
      }
    }

    // Gắn click (thêm 1 listener nữa cũng không sao)
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
    logTabs2("Initialized V2, default tab =", defaultSelector);

    window.vspTabsShow2 = showTab;
  }

  function runAll() {
    ensurePanes();
    initTabs2();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runAll);
  } else {
    runAll();
  }
})();
JS_EOF

echo "[OK] Appended autowrap+tabs V2 vào $JS"
