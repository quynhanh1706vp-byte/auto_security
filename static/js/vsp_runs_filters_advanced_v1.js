(function(){

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_filters_advanced_v1.js", "hash=", location.hash); } catch(_){}
    return;
  }

  // === VSP_DISABLE_RUNS_FILTER_ADV_V1_BY_MASTER ===
  if (window.VSP_COMMERCIAL_RUNS_MASTER) return;
  // === END VSP_DISABLE_RUNS_FILTER_ADV_V1_BY_MASTER ===
})();
(function(){/*VSP_DISABLE_RUNS_FILTERS_V1*/return;})();
(function(){return;})();
(function () {
  console.log("[VSP_RUNS_FILTER] vsp_runs_filters_advanced_v1.js loaded");

  function findRunsPane() {
    var pane =
      document.getElementById("vsp-tab-runs-main") ||
      document.querySelector("[data-vsp-pane='runs']") ||
      document.querySelector("#vsp-tab-runs") ||
      document.querySelector(".vsp-pane-runs");

    if (pane) return pane;

    // fallback: tìm theo text "Runs & Reports"
    var all = Array.from(document.querySelectorAll("section,div,main"));
    var marker = all.find(function (el) {
      var t = (el.textContent || "").toUpperCase();
      return t.includes("RUNS & REPORTS") && t.includes("/API/VSP/RUNS_INDEX_V3");
    });
    if (marker) {
      return marker.closest(".vsp-pane") || marker.closest("section") || marker.closest("div");
    }
    return null;
  }

  function applyFilters() {
    var pane = findRunsPane();
    if (!pane) return;

    var tbody = pane.querySelector("tbody");
    if (!tbody) return;

    var rows = Array.from(tbody.querySelectorAll("tr"));
    if (!rows.length) return;

    var idFilter = (document.getElementById("vsp-runs-filter-id") || {}).value || "";
    var statusFilter = (document.getElementById("vsp-runs-filter-status") || {}).value || "";
    var dateFrom = (document.getElementById("vsp-runs-filter-date-from") || {}).value || "";
    var dateTo = (document.getElementById("vsp-runs-filter-date-to") || {}).value || "";

    idFilter = idFilter.trim().toLowerCase();
    statusFilter = statusFilter.trim().toUpperCase();

    rows.forEach(function (tr) {
      var tds = tr.querySelectorAll("td");
      if (!tds.length) return;

      var runId = (tds[0].textContent || "").toLowerCase();   // Run ID
      var started = (tds[2] && tds[2].textContent) || "";      // Started
      var status = (tds[4] && tds[4].textContent) || "";       // Status

      var visible = true;

      if (idFilter && !runId.includes(idFilter)) visible = false;

      if (statusFilter && status.toUpperCase().indexOf(statusFilter) === -1) visible = false;

      if (dateFrom) {
        var m = started.match(/(\d{2})\/(\d{2})\/(\d{4})/);
        if (m) {
          var d = m[3] + "-" + m[2] + "-" + m[1];
          if (d < dateFrom) visible = false;
        }
      }

      if (dateTo) {
        var m2 = started.match(/(\d{2})\/(\d{2})\/(\d{4})/);
        if (m2) {
          var d2 = m2[3] + "-" + m2[2] + "-" + m2[1];
          if (d2 > dateTo) visible = false;
        }
      }

      tr.style.display = visible ? "" : "none";
    });
  }

  function initFilters() {
    var pane = findRunsPane();
    if (!pane) {
      console.warn("[VSP_RUNS_FILTER] Không tìm thấy pane Runs.");
      return;
    }
    if (pane.querySelector("#vsp-runs-filter-bar")) return;

    var wrapper = document.createElement("div");
    wrapper.id = "vsp-runs-filter-bar";
    wrapper.className = "vsp-card";
    wrapper.style.margin = "16px 0";

    wrapper.innerHTML = `
      <div class="vsp-card-title">Filters</div>
      <div class="vsp-grid vsp-grid-4" style="gap:12px; margin-top:8px;">
        <div>
          <label>Run ID / profile / target</label>
          <input id="vsp-runs-filter-id" type="text" placeholder="search..." style="width:100%;">
        </div>
        <div>
          <label>Status</label>
          <select id="vsp-runs-filter-status" style="width:100%;">
            <option value="">Any</option>
            <option value="DONE">DONE</option>
            <option value="FAILED">FAILED</option>
            <option value="RUNNING">RUNNING</option>
          </select>
        </div>
        <div>
          <label>Date from</label>
          <input id="vsp-runs-filter-date-from" type="date" style="width:100%;">
        </div>
        <div>
          <label>Date to</label>
          <input id="vsp-runs-filter-date-to" type="date" style="width:100%;">
        </div>
      </div>
    `;

    var header = pane.querySelector("h2, h3, .vsp-section-title");
    if (header && header.parentNode) {
      header.parentNode.insertBefore(wrapper, header.nextSibling);
    } else {
      pane.insertBefore(wrapper, pane.firstChild);
    }

    ["vsp-runs-filter-id", "vsp-runs-filter-status",
     "vsp-runs-filter-date-from", "vsp-runs-filter-date-to"].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      el.addEventListener("input", applyFilters);
      el.addEventListener("change", applyFilters);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (location.hash === "#runs") {
      setTimeout(function () {
        initFilters();
        applyFilters();
      }, 400);
    }
  });

  window.addEventListener("hashchange", function () {
    if (location.hash === "#runs") {
      setTimeout(function () {
        initFilters();
        applyFilters();
      }, 400);
    }
  });
})();
