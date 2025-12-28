/*
 * VSP 2025 – Runs & Reports legacy stub
 * File này CHỈ để tránh crash từ các template cũ còn gọi loadRunsTable().
 * Tuyệt đối không dùng logic VSP_RUNS_UI_V1 nữa.
 */
const VSP_RUNS_REPORTS_LOG = "[VSP_RUNS_REPORTS_STUB]";

console.log(VSP_RUNS_REPORTS_LOG, "loaded – legacy runs-report features are disabled.");

window.loadRunsTable = function () {
  // Nếu template cũ còn gọi loadRunsTable(), chỉ log 1 dòng nhẹ rồi bỏ qua.
  console.log(VSP_RUNS_REPORTS_LOG, "loadRunsTable() called – ignoring legacy implementation.");
};
