(function () {

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_tab_loader_v1.js", "hash=", location.hash); } catch(_){}
    return;
  }

  const LOG_PREFIX = "[VSP_RUNS_TAB2]";
  const API_URL = "/api/vsp/runs_v3";
  const TBODY_ID = "vsp-runs-tbody";

  function log() {
    console.log(LOG_PREFIX, ...arguments);
  }
  function warn() {
    console.warn(LOG_PREFIX, ...arguments);
  }

  function sev(run, key) {
    if (!run) return 0;
    const by = run.by_severity || run.severity_buckets || {};
    return by[key] || 0;
  }

  function buildRow(run, idx) {
    const tr = document.createElement('tr');

    const runId   = run.run_id || run.id || ("RUN_" + (idx + 1));
    const ts      = run.ts_start || run.started_at || run.start_time || run.created_at || "";
    const profile = run.profile || run.scan_profile || run.mode || run.run_profile || run.kind || "–";
    const srcPath = run.src_path || run.source_folder || run.source_root || run.module || run.project || "–";
    const url     = run.target_url || run.target || run.app_origin || run.url || run.repo || "–";

    const crit  = sev(run, "CRITICAL") || "–";
    const high  = sev(run, "HIGH")     || "–";
    const med   = sev(run, "MEDIUM")   || "–";
    const low   = sev(run, "LOW")      || "–";
    const info  = sev(run, "INFO")     || "–";
    const trace = sev(run, "TRACE")    || "–";

    let total;
    if (typeof run.total_findings === "number") {
      total = run.total_findings;
    } else {
      const by = run.by_severity || {};
      total = Object.values(by).reduce(
        (a, v) => a + (typeof v === "number" ? v : 0),
        0
      );
      if (!total) total = "–";
    }

    const toolsArr = run.tools_enabled || run.tools || run.enabled_tools || run.profiles_tools || [];
    const tools =
      Array.isArray(toolsArr) ? (toolsArr.length ? toolsArr.join(", ") : "–")
                              : (toolsArr || "–");

    tr.innerHTML =
      '<td><span class="mono">' + runId + '</span></td>' +
      '<td>' + (ts || '–') + '</td>' +
      '<td>' + profile + '</td>' +
      '<td>' + srcPath + '</td>' +
      '<td>' + url + '</td>' +
      '<td>' + crit + '</td>' +
      '<td>' + high + '</td>' +
      '<td>' + med + '</td>' +
      '<td>' + low + '</td>' +
      '<td>' + info + '</td>' +
      '<td>' + trace + '</td>' +
      '<td>' + total + '</td>' +
      '<td>' + tools + '</td>' +
      '<td>HTML · PDF · CSV</td>';

    return tr;
  }

  async function loadRunsTable() {
    const tbody = document.getElementById(TBODY_ID);
    if (!tbody) {
      warn("Không tìm thấy tbody#" + TBODY_ID);
      return;
    }

    tbody.innerHTML =
      '<tr><td colspan="14" style="color:#fff;padding:8px;">Đang tải RUN history...</td></tr>';

    let resp;
    try {
      resp = await fetch(API_URL, {
        headers: { Accept: "application/json" },
      });
    } catch (e) {
      warn("Lỗi fetch:", e);
      tbody.innerHTML =
        '<tr><td colspan="14" style="color:#fff;padding:8px;">Không kết nối được tới API runs_v3.</td></tr>';
      return;
    }

    if (!resp.ok) {
      warn("API error", resp.status, resp.statusText);
      tbody.innerHTML =
        '<tr><td colspan="14" style="color:#fff;padding:8px;">API runs_v3 trả lỗi ' +
        resp.status +
        '.</td></tr>';
      return;
    }

    let data;
    try {
      data = await resp.json();
    } catch (e) {
      warn("Lỗi parse JSON:", e);
      tbody.innerHTML =
        '<tr><td colspan="14" style="color:#fff;padding:8px;">Lỗi parse JSON từ API runs_v3.</td></tr>';
      return;
    }

    let runs = data && (data.items || data.runs || data);
    if (!Array.isArray(runs)) {
      warn("Định dạng bất ngờ:", data);
      runs = [];
    }

    tbody.innerHTML = "";

    if (!runs.length) {
      tbody.innerHTML =
        '<tr><td colspan="14" style="color:#fff;padding:8px;">Chưa có RUN nào trong hệ thống.</td></tr>';
      log("No runs.");
      return;
    }

    runs.forEach((run, idx) => {
      tbody.appendChild(buildRow(run, idx));
    });

    log("Rendered", runs.length, "runs.");
  }

  window.addEventListener("load", function () {
    log("window.load → loadRunsTable()");
    loadRunsTable();
  });

  window.VSP_RUNS = window.VSP_RUNS || {};
  window.VSP_RUNS.loadRunsTable = loadRunsTable;
})();
