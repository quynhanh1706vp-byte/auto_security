// ======================= VSP_PATCH_5TABS_V2_BASELINE_V1 =======================
//
// File này giữ vai trò "patch container" cho UI 5 tab.
// Hiện tại chỉ log nhẹ để tránh 404 / SyntaxError.
// Tất cả logic chính về dashboard, runs, datasource, settings, overrides
// đang được xử lý trong các file JS khác (vd: vsp_dashboard_live_v2.js, vsp_ui_main.js).
//
// Khi cần thêm patch mới (extras, top risk, noisy paths...), sẽ tạo file JS riêng.

document.addEventListener("DOMContentLoaded", () => {
  try {
    console.log("[VSP_PATCH_5TABS_V2] baseline loaded");
    // Chưa có patch bổ sung nào ở V1.
  } catch (err) {
    console.error("[VSP_PATCH_5TABS_V2][ERR]", err);
  }
});
