function vspAdjustDashboardScale() {
  var tab = document.getElementById('tab-dashboard');
  if (!tab) return;

  // Reset để đo đúng chiều cao thật
  tab.style.transform = 'none';
  tab.style.transformOrigin = 'top center';

  // Chừa phần header + margin trên/dưới
  var headerReserve = 160; // tăng lên một chút cho an toàn
  var viewport = window.innerHeight - headerReserve;
  if (viewport <= 0) return;

  var full = tab.scrollHeight;
  if (!full || full <= 0) return;

  // Tính scale để full dashboard vừa trong viewport
  var scale = viewport / full;
  if (scale > 1) scale = 1;     // nếu nhỏ sẵn thì giữ nguyên
  if (scale < 0.7) scale = 0.7; // không cho nhỏ quá

  tab.style.transform = 'scale(' + scale + ')';
  tab.style.transformOrigin = 'top center';
}

window.addEventListener('load', vspAdjustDashboardScale);
window.addEventListener('resize', vspAdjustDashboardScale);
