/**
 * VSP SETTINGS – PROFILE + LAST RUN + TOOL STACK
 * - Chỉ áp dụng cho tab #tab-settings
 * - Không tạo thanh cuộn bên trong; dùng layout 2 cột, full màn hình.
 */

(function () {
  if (!window.VSP) window.VSP = {};

  // Helper: tạo 1 element
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (typeof text === "string") node.textContent = text;
    return node;
  }

  // Render chính
  function renderSettings(root, settings) {
    if (!root) return;
    if (!settings) settings = {};

    var profile = settings.profile || "EXT";
    var runId   = settings.last_run_id || "—";
    var tools   = Array.isArray(settings.tools) ? settings.tools : [];

    // Layout tổng
    var wrap = el("div", "vsp-settings-layout");

    // --- Cột trái: PROFILE + LAST RUN ---
    var colLeft = el("div", "vsp-settings-col-left");
    var cardInfo = el("div", "vsp-card vsp-settings-card");

    var profileLabel = el("div", "vsp-label", "PROFILE");
    var profileVal   = el("div", "vsp-value", profile);

    var runLabel = el("div", "vsp-label mt-32", "LAST RUN ID");
    var runVal   = el("div", "vsp-value", runId);

    cardInfo.appendChild(profileLabel);
    cardInfo.appendChild(profileVal);
    cardInfo.appendChild(runLabel);
    cardInfo.appendChild(runVal);
    colLeft.appendChild(cardInfo);

    // --- Cột phải: TOOL STACK TABLE ---
    var colRight = el("div", "vsp-settings-col-right");
    var cardTools = el("div", "vsp-card vsp-settings-card");

    var header = el("div", "vsp-card-header");
    var title = el("div", "vsp-card-title", "Tool Stack (" + tools.length + " tools)");
    header.appendChild(title);
    cardTools.appendChild(header);

    // Table wrapper (không tạo scroll riêng)
    var tableWrap = el("div", "vsp-table-wrapper");
    var table = el("table", "vsp-table");

    var thead = el("thead");
    var trHead = el("tr");
    ["Tool", "Type", "Enabled"].forEach(function (h) {
      var th = el("th", "", h.toUpperCase());
      trHead.appendChild(th);
    });
    thead.appendChild(trHead);
    table.appendChild(thead);

    var tbody = el("tbody");
    tools.forEach(function (t) {
      var tr = el("tr");
      var tdTool = el("td", "", t.name || t.key || "");
      var tdType = el("td", "", t.type || "");
      var tdEn   = el("td", "", (t.enabled === false || t.enabled === "OFF") ? "OFF" : "ON");
      tr.appendChild(tdTool);
      tr.appendChild(tdType);
      tr.appendChild(tdEn);
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);

    tableWrap.appendChild(table);
    cardTools.appendChild(tableWrap);
    colRight.appendChild(cardTools);

    wrap.appendChild(colLeft);
    wrap.appendChild(colRight);

    // Ghi vào tab-settings
    root.innerHTML = "";
    root.appendChild(wrap);
  }

  // Gọi API settings rồi render
  function fetchAndRender() {
    var root = document.getElementById("tab-settings");
    if (!root) return;

    fetch("/api/vsp/settings")
      .then(function (resp) { return resp.json(); })
      .then(function (data) {
        renderSettings(root, data || {});
      })
      .catch(function (e) {
        if (window.console && console.error) {
          console.error("[VSP][SETTINGS] Lỗi gọi API /api/vsp/settings:", e);
        }
      });
  }

  document.addEventListener("DOMContentLoaded", function () {
    // Đợi DOM sẵn sàng, sau đó render
    setTimeout(fetchAndRender, 300);
  });
})();
