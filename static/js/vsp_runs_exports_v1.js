/**
 * VSP Runs Export – v1
 *
 * Gắn onclick cho các nút Export trên TAB 2 – RUNS & REPORTS.
 *
 * Yêu cầu HTML:
 *   <button id="vsp-runs-btn-export-index-csv">Export run index (CSV)</button>
 *   <button id="vsp-runs-btn-export-findings-json">Export findings (JSON)</button>
 *   <button id="vsp-runs-btn-export-sbom">Export SBOM</button>
 *   <button id="vsp-runs-btn-export-license">Export License report</button>
 *
 * Các API phía server:
 *   GET /api/vsp/export/runs_index_csv
 *   GET /api/vsp/export/findings_json
 *   GET /api/vsp/export/sbom
 *   GET /api/vsp/export/license
 *
 * Mặc định: không truyền run_id => server export run mới nhất.
 * Nếu muốn export theo run cụ thể, bạn có thể sửa hàm buildUrl
 * để thêm query ?run_id=... khi cần.
 */

(function () {

  // VSP_ROUTE_GUARD_RUNS_ONLY_V1
  function __vsp_is_runs_only_v1(){
    try {
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    } catch(_) { return false; }
  }
  if(!__vsp_is_runs_only_v1()){
    try{ console.info("[VSP_ROUTE_GUARD_RUNS_ONLY_V1] skip", "vsp_runs_exports_v1.js", "hash=", location.hash); } catch(_){}
    return;
  }

  console.log("[VSP_RUNS_EXPORT] vsp_runs_exports_v1.js loaded.");

  function bindClick(buttonId, buildUrl) {
    var btn = document.getElementById(buttonId);
    if (!btn) {
      console.warn("[VSP_RUNS_EXPORT] Button not found:", buttonId);
      return;
    }
    btn.addEventListener("click", function (evt) {
      evt.preventDefault();
      var url = buildUrl();
      if (!url) {
        console.error("[VSP_RUNS_EXPORT] No URL for button:", buttonId);
        return;
      }
      console.log("[VSP_RUNS_EXPORT] Download ->", url);
      // Cách đơn giản nhất: mở URL => trình duyệt tự download.
      window.location.href = url;
    });
  }

  // Nếu sau này bạn muốn export theo run cụ thể,
  // có thể tìm run_id từ dòng được chọn trên bảng:
  function getSelectedRunIdFromTable() {
    // Placeholder, hiện tại không dùng.
    // Bạn có thể gắn class "is-selected" cho <tr> rồi đọc dataset.runId.
    return null;
  }

  // 1) Export run index (CSV)
  bindClick("vsp-runs-btn-export-index-csv", function () {
    // Nếu cần run_id cụ thể:
    // var runId = getSelectedRunIdFromTable();
    // return runId ? "/api/vsp/export/runs_index_csv?run_id=" + encodeURIComponent(runId)
    //              : "/api/vsp/export/runs_index_csv";
    return "/api/vsp/export/runs_index_csv";
  });

  // 2) Export 
  bindClick("vsp-runs-btn-export-findings-json", function () {
    // var runId = getSelectedRunIdFromTable();
    // return runId ? "/api/vsp/export/findings_json?run_id=" + encodeURIComponent(runId)
    //              : "/api/vsp/export/findings_json";
    return "/api/vsp/export/findings_json";
  });

  // 3) Export SBOM
  bindClick("vsp-runs-btn-export-sbom", function () {
    // var runId = getSelectedRunIdFromTable();
    // return runId ? "/api/vsp/export/sbom?run_id=" + encodeURIComponent(runId)
    //              : "/api/vsp/export/sbom";
    return "/api/vsp/export/sbom";
  });

  // 4) Export License report
  bindClick("vsp-runs-btn-export-license", function () {
    // var runId = getSelectedRunIdFromTable();
    // return runId ? "/api/vsp/export/license?run_id=" + encodeURIComponent(runId)
    //              : "/api/vsp/export/license";
    return "/api/vsp/export/license";
  });
})();
