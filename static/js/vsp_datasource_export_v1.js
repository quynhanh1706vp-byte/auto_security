;(function () {
  const LOG_PREFIX = "[VSP_DS_EXPORT]";

  function $(id) {
    return document.getElementById(id);
  }

  function createButton(text, id) {
    const btn = document.createElement("button");
    btn.id = id;
    btn.type = "button";
    btn.className = "vsp-btn vsp-btn-pill";
    btn.textContent = text;
    return btn;
  }

  function injectButtons() {
    // Tìm toolbar Data Source nếu có
    let toolbar = $("vsp-ds-toolbar");
    const pane = document.getElementById("vsp-tab-datasource");

    if (!toolbar && pane) {
      // Nếu template chưa có toolbar riêng, tạo 1 div nhỏ ở đầu tab Data Source
      toolbar = document.createElement("div");
      toolbar.id = "vsp-ds-toolbar";
      toolbar.className = "vsp-ds-toolbar vsp-flex vsp-justify-between vsp-items-center vsp-mb-3";

      // Đưa toolbar lên đầu tab Data Source
      if (pane.firstChild) {
        pane.insertBefore(toolbar, pane.firstChild);
      } else {
        pane.appendChild(toolbar);
      }
    }

    if (!toolbar) {
      console.log(LOG_PREFIX, "Không thấy Data Source toolbar / pane – skip inject.");
      return;
    }

    // Tránh chèn trùng
    if (document.getElementById("vsp-ds-export-json")) {
      console.log(LOG_PREFIX, "Export buttons đã tồn tại – bỏ qua.");
      return;
    }

    const rightBox = document.createElement("div");
    rightBox.className = "vsp-ds-export-group";

    const btnJson = createButton("Export JSON", "vsp-ds-export-json");
    const btnCsv = createButton("Export CSV", "vsp-ds-export-csv");

    rightBox.appendChild(btnJson);
    rightBox.appendChild(btnCsv);
    toolbar.appendChild(rightBox);

    // Bind click
    btnJson.addEventListener("click", function () {
      const url = "/api/vsp/datasource_export_v1?fmt=json";
      console.log(LOG_PREFIX, "Export JSON:", url);
      window.open(url, "_blank");
    });

    btnCsv.addEventListener("click", function () {
      const url = "/api/vsp/datasource_export_v1?fmt=csv";
      console.log(LOG_PREFIX, "Export CSV:", url);
      window.open(url, "_blank");
    });

    console.log(LOG_PREFIX, "Injected Export JSON/CSV buttons.");
  }

  function init() {
    const pane = document.getElementById("vsp-tab-datasource");
    if (!pane) {
      console.log(LOG_PREFIX, "Không trong layout có Data Source tab – skip.");
      return;
    }
    injectButtons();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  console.log(LOG_PREFIX, "vsp_datasource_export_v1.js loaded.");
})();
