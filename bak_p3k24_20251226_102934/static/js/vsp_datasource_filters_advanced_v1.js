(function () {
  console.log("[VSP_DS_FILTER] vsp_datasource_filters_advanced_v1.js loaded");

  function findDatasourcePane() {
    var pane =
      document.getElementById("vsp-tab-datasource-main") ||
      document.querySelector("[data-vsp-pane='datasource']") ||
      document.querySelector("#vsp-tab-datasource") ||
      document.querySelector(".vsp-pane-datasource");

    if (pane) return pane;

    // fallback theo text "DATA SOURCE" + "/api/vsp/datasource_v2"
    var all = Array.from(document.querySelectorAll("section,div,main"));
    var marker = all.find(function (el) {
      var t = (el.textContent || "").toUpperCase();
      return t.includes("DATA SOURCE") && t.includes("/API/VSP/DATASOURCE_V2");
    });
    if (marker) {
      return marker.closest(".vsp-pane") || marker.closest("section") || marker.closest("div");
    }
    return null;
  }

  function applyFilters() {
    var pane = findDatasourcePane();
    if (!pane) return;

    var tbody = pane.querySelector("tbody");
    if (!tbody) return;

    var rows = Array.from(tbody.querySelectorAll("tr"));
    if (!rows.length) return;

    var sev = (document.getElementById("vsp-ds-filter-sev") || {}).value || "";
    var tool = (document.getElementById("vsp-ds-filter-tool") || {}).value || "";
    var q = (document.getElementById("vsp-ds-filter-q") || {}).value || "";

    sev = sev.toUpperCase();
    tool = tool.toLowerCase();
    q = q.toLowerCase();

    rows.forEach(function (tr) {
      var tds = tr.querySelectorAll("td");
      if (!tds.length) return;

      var sevCell = (tds[1] && tds[1].textContent) || "";  // Sev
      var toolCell = (tds[2] && tds[2].textContent) || ""; // Tool
      var rowText = tr.textContent || "";

      var visible = true;

      if (sev && sevCell.toUpperCase() !== sev) visible = false;

      if (tool && toolCell.toLowerCase() !== tool) visible = false;

      if (q && rowText.toLowerCase().indexOf(q) === -1) visible = false;

      tr.style.display = visible ? "" : "none";
    });
  }

  function collectToolsOptions(pane) {
    var tbody = pane.querySelector("tbody");
    if (!tbody) return [];
    var tools = new Set();
    Array.from(tbody.querySelectorAll("tr")).forEach(function (tr) {
      var tds = tr.querySelectorAll("td");
      if (tds[2]) {
        var t = (tds[2].textContent || "").trim();
        if (t) tools.add(t);
      }
    });
    return Array.from(tools).sort();
  }

  function initFilters() {
    var pane = findDatasourcePane();
    if (!pane) {
      console.warn("[VSP_DS_FILTER] Không tìm thấy pane Data Source.");
      return;
    }

    if (pane.querySelector("#vsp-ds-filter-bar")) return;

    var wrapper = document.createElement("div");
    wrapper.id = "vsp-ds-filter-bar";
    wrapper.className = "vsp-card";
    wrapper.style.margin = "16px 0";

    var tools = collectToolsOptions(pane);
    var toolsOptions = ['<option value="">Any</option>'].concat(
      tools.map(function (t) {
        return '<option value="' + t + '">' + t + "</option>";
      })
    ).join("");

    wrapper.innerHTML = `
      <div class="vsp-card-title">Filters</div>
      <div class="vsp-grid vsp-grid-3" style="gap:12px; margin-top:8px;">
        <div>
          <label>Severity</label>
          <select id="vsp-ds-filter-sev" style="width:100%;">
            <option value="">Any</option>
            <option value="CRITICAL">CRITICAL</option>
            <option value="HIGH">HIGH</option>
            <option value="MEDIUM">MEDIUM</option>
            <option value="LOW">LOW</option>
            <option value="INFO">INFO</option>
            <option value="TRACE">TRACE</option>
          </select>
        </div>
        <div>
          <label>Tool</label>
          <select id="vsp-ds-filter-tool" style="width:100%;">
            ${toolsOptions}
          </select>
        </div>
        <div>
          <label>Search (rule / path / CWE)</label>
          <input id="vsp-ds-filter-q" type="text" placeholder="text contains…" style="width:100%;">
        </div>
      </div>
    `;

    var header = pane.querySelector("h2, h3, .vsp-section-title");
    if (header && header.parentNode) {
      header.parentNode.insertBefore(wrapper, header.nextSibling);
    } else {
      pane.insertBefore(wrapper, pane.firstChild);
    }

    ["vsp-ds-filter-sev", "vsp-ds-filter-tool", "vsp-ds-filter-q"].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      el.addEventListener("input", applyFilters);
      el.addEventListener("change", applyFilters);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (location.hash === "#datasource") {
      setTimeout(function () {
        initFilters();
        applyFilters();
      }, 400);
    }
  });

  window.addEventListener("hashchange", function () {
    if (location.hash === "#datasource") {
      setTimeout(function () {
        initFilters();
        applyFilters();
      }, 400);
    }
  });
})();
