/**
 * SB RUN PANEL – UI ONLY
 * File stub: không chạy scan thật, chỉ log ra console.
 * Dùng để tránh black screen nếu backend/CLI chưa wire xong.
 */
document.addEventListener('DOMContentLoaded', function () {
  var btn =
    document.querySelector('.sb-run-card button') ||
    document.querySelector('#sb-run-btn');

  if (!btn) {
    console.log('[SB-RUN] Không tìm thấy nút RUN trên UI (stub).');
    return;
  }

  btn.addEventListener('click', function (ev) {
    console.log('[SB-RUN] Click RUN (UI only – không chạy scan thật).');
    // Không redirect, không fetch API, không overlay – để nguyên UI.
    // Nếu sau này muốn gọi CLI/API thì sửa file này.
  });
});
