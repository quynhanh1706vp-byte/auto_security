/* VSP_GATE_RUNS_WRAPPER_V2_SAFE */
(function(){
  'use strict';
  function __vsp_is_runs(){
    try {
      const h = (location.hash || '').toLowerCase();
      return h.startsWith('#runs') || h.includes('#runs/');
    } catch(e) {
      return false;
    }
  }
  if(!__vsp_is_runs()){
    try{ console.info('[VSP_GATE_RUNS_WRAPPER_V2_SAFE] skip', 'vsp_runs_v1.js', 'hash=', location.hash); } catch(_e){}
    return;
  }

// VSP_RUNS_V1_REAL – dùng data thật từ /api/vsp/runs_v3
// API trả về ARRAY các run, không phải { runs: [...] } nữa.

(function () {
  const LOG = "[VSP_RUNS_TAB]";
  const RUNS_API = "/api/vsp/runs_v3";

  function fmtInt(x) {
    if (x === null || x === undefined) return "-";
    const n = Number(x);
    if (!Number.isFinite(n)) return "-";
    return n.toLocaleString("en-US");
  }

  function fmtDate(s) {
    if (!s) return "-";
    return s;
  }

  async function fetchRunsIndex() {
    console.log(LOG, "Fetch", RUNS_API);
    const res = await fetch(RUNS_API, { cache: "no-store" });
    if (!res.ok) {
      console.error(LOG, "HTTP error", res.status, res.statusText);
      return [];
    }
    const data = await res.json();

    if (Array.isArray(data)) {
      console.log(LOG, "Got array runs:", data.length);
      return data;
    }

    if (Array.isArray(data.runs)) {
      console.warn(LOG, "Got legacy object with .runs – dùng .runs", data.runs.length);
      return data.runs;
    }

    console.error(LOG, "Không nhận diện được format runs_v3:", data);
    return [];
  }

  function renderKpi(runs) {
    const totalRuns = runs.length;
    const totalFindings = runs.reduce((acc, r) => acc + (Number(r.total_findings) || 0), 0);
    const last10 = runs.slice(-10);
    const totalFindLast10 = last10.reduce((acc, r) => acc + (Number(r.total_findings) || 0), 0);
    const avgLast10 = last10.length ? Math.round(totalFindLast10 / last10.length) : 0;

    const elTotalRuns = document.querySelector("[data-vsp-runs-kpi='total-runs']");
    const elLast10Avg = document.querySelector("[data-vsp-runs-kpi='avg-last10']");
    const elLast10Count = document.querySelector("[data-vsp-runs-kpi='last10-count']");

    if (elTotalRuns) elTotalRuns.textContent = fmtInt(totalRuns);
    if (elLast10Avg) elLast10Avg.textContent = avgLast10 ? fmtInt(avgLast10) : "-";
    if (elLast10Count) elLast10Count.textContent = fmtInt(last10.length);

    console.log(LOG, "KPI updated. totalRuns =", totalRuns, "avgLast10 =", avgLast10);
  }

  function renderRunsTable(runs) {
    const tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) {
      console.warn(LOG, "Không tìm thấy #vsp-runs-tbody – bỏ qua render bảng.");
      return;
    }

    tbody.innerHTML = "";

    runs.forEach((run, idx) => {
      const tr = document.createElement("tr");

      const colIndex = document.createElement("td");
      colIndex.textContent = String(idx + 1);
      tr.appendChild(colIndex);

      const colRunId = document.createElement("td");
      colRunId.textContent = run.run_id || "-";
      tr.appendChild(colRunId);

      const colProfile = document.createElement("td");
      colProfile.textContent = run.profile || "UNKNOWN";
      tr.appendChild(colProfile);

      const colTotal = document.createElement("td");
      colTotal.textContent = fmtInt(run.total_findings);
      tr.appendChild(colTotal);

      const colCrit = document.createElement("td");
      colCrit.textContent = fmtInt(run.total_critical);
      tr.appendChild(colCrit);

      const colHigh = document.createElement("td");
      colHigh.textContent = fmtInt(run.total_high);
      tr.appendChild(colHigh);

      const colMedium = document.createElement("td");
      colMedium.textContent = fmtInt(run.total_medium);
      tr.appendChild(colMedium);

      const colLow = document.createElement("td");
      colLow.textContent = fmtInt(run.total_low);
      tr.appendChild(colLow);

      const colInfo = document.createElement("td");
      colInfo.textContent = fmtInt(run.total_info);
      tr.appendChild(colInfo);

      const colTrace = document.createElement("td");
      colTrace.textContent = fmtInt(run.total_trace);
      tr.appendChild(colTrace);

      const colStarted = document.createElement("td");
      colStarted.textContent = fmtDate(run.started_at);
      tr.appendChild(colStarted);

      const colFinished = document.createElement("td");
      colFinished.textContent = fmtDate(run.finished_at);
      tr.appendChild(colFinished);

      tbody.appendChild(tr);
    });

    console.log(LOG, "Rendered", runs.length, "runs vào #vsp-runs-tbody");
  }

  async function loadRunsTab() {
    try {
      const runs = await fetchRunsIndex();
      renderKpi(runs);
      renderRunsTable(runs);
    } catch (err) {
      console.error(LOG, "Lỗi loadRunsTab:", err);
    }
  }

  // Expose để script khác có thể gọi lại nếu cần
  window.vspLoadRunsTab = loadRunsTab;

  document.addEventListener("DOMContentLoaded", function () {
    // Auto-load nếu TAB Runs đang active sẵn
    const tabPane = document.getElementById("tab-runs");
    if (tabPane && tabPane.classList.contains("tab-pane") && tabPane.classList.contains("active")) {
      console.log(LOG, "tab-runs active sẵn – auto loadRunsTab()");
      loadRunsTab();
    }

    // Bind nút TAB 2 – Runs & Reports
    const tabBtn = document.querySelector("[data-tab-target='tab-runs']");
    if (tabBtn) {
      tabBtn.addEventListener("click", function () {
        console.log(LOG, "switch to TAB Runs – loadRunsTab()");
        loadRunsTab();
      });
    } else {
      console.warn(LOG, "Không tìm thấy nút TAB 2 (data-tab-target='tab-runs').");
    }
  });
})();

})();
