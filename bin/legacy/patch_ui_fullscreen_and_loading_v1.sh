#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/style.css"
INDEX="$ROOT/templates/index.html"

echo "[i] ROOT  = $ROOT"
echo "[i] CSS   = $CSS"
echo "[i] INDEX = $INDEX"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

########################################
# 1) Bơm CSS: fullscreen + nav + chart
########################################
echo "[i] Append CSS layout mới vào $CSS"

cat >> "$CSS" <<'CSS_EOF'

/* ==== V2 – FULLSCREEN LAYOUT + NAV + LOADING ==== */

/* Full height, bỏ margin trắng xung quanh */
html, body {
  height: 100%;
  margin: 0;
  padding: 0;
}

/* Cho khối chính rộng hơn, sát 2 bên hơn một chút */
main, .main-container, .page-wrapper, .page-content {
  max-width: 1600px;
  margin: 0 auto;
  padding: 16px 24px 40px 24px;
}

/* Accent chính: dùng lại màu gần giống nút Run (xanh lá) */
:root {
  --sb-accent: #1ed760;    /* xanh lá kiểu nút Run scan */
  --sb-accent-hover: #24e46a;
}

/* Nav item – 4 tab Dashboard / Run & Report / Settings / Data Source */
.nav-item a,
.nav-item a:visited {
  display: block;
  padding: 6px 16px;
  border-radius: 999px;
  background: var(--sb-accent);
  color: #031016;
  font-size: 13px;
  font-weight: 600;
  text-decoration: none;
  transition: background 0.2s ease, transform 0.1s ease, box-shadow 0.1s ease;
}

/* Tab đang active – cho nổi hơn chút */
.nav-item a.active,
.nav-item a[aria-current="page"] {
  background: var(--sb-accent-hover);
  box-shadow: 0 0 0 1px rgba(255,255,255,0.35);
}

/* Hover */
.nav-item a:hover {
  background: var(--sb-accent-hover);
  transform: translateY(-1px);
}

/* Chuyển nav sang dạng dọc (best-effort) */
.nav-item {
  display: block;
  margin: 4px 0;
}

/* Nếu container nav đang flex ngang thì ép nó xếp dọc + cho sát nhau */
.nav, .top-nav, .nav-container, .header-nav {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

/* Với các màn hình nhỏ, cho nav full-width bên trên */
@media (max-width: 900px) {
  .nav, .top-nav, .nav-container, .header-nav {
    align-items: stretch;
  }
}

/* === Loading state cho nút Run scan === */
#btn-run-scan.btn-loading {
  position: relative;
  opacity: 0.8;
  cursor: wait;
}

/* Spinner nhỏ trong nút Run */
#btn-run-scan .sb-spinner {
  display: inline-block;
  width: 14px;
  height: 14px;
  margin-right: 6px;
  border-radius: 50%;
  border: 2px solid rgba(0,0,0,0.25);
  border-top-color: rgba(0,0,0,0.75);
  animation: sb-spin 0.6s linear infinite;
  vertical-align: -2px;
}

@keyframes sb-spin {
  to { transform: rotate(360deg); }
}

/* Đẩy chart severity lên gần top hơn (best-effort) */
#severity-chart,
#severityChart,
#severity_chart_canvas {
  margin-top: 16px;
}

/* Nếu chart nằm trong grid/flex, cho ưu tiên đứng trên */
#severity-chart,
#severityChart,
#severity_chart_canvas {
  order: -1;
}

/* Giữ layout ở desktop: card + chart không bị bó hẹp quá */
.dashboard-grid,
.dashboard-cols {
  display: grid;
  grid-template-columns: minmax(0, 2fr) minmax(0, 1.2fr);
  gap: 16px;
}
@media (max-width: 1100px) {
  .dashboard-grid,
  .dashboard-cols {
    grid-template-columns: minmax(0, 1fr);
  }
}

CSS_EOF

########################################
# 2) Tạo JS: trạng thái loading khi nhấn Run
########################################
JS="$ROOT/static/run_scan_loading.js"
echo "[i] Ghi JS loading nút Run vào $JS"

cat > "$JS" <<'JS_EOF';
document.addEventListener('DOMContentLoaded', function () {
  var btn = document.getElementById('btn-run-scan');
  if (!btn) {
    console.warn('[SB-LOADING] Không tìm thấy #btn-run-scan');
    return;
  }

  var originalHtml = btn.innerHTML;
  var timeoutId = null;

  function startLoading() {
    if (btn.classList.contains('btn-loading')) return;

    btn.classList.add('btn-loading');
    btn.disabled = true;
    btn.innerHTML =
      '<span class="sb-spinner"></span>' +
      '<span>Đang chạy scan…</span>';
  }

  function stopLoading() {
    btn.classList.remove('btn-loading');
    btn.disabled = false;
    btn.innerHTML = originalHtml;
  }

  // Khi click nút Run scan -> bật loading
  btn.addEventListener('click', function () {
    startLoading();

    // Fallback: sau 60s thì tự tắt, tránh kẹt vĩnh viễn nếu API lỗi
    if (timeoutId) clearTimeout(timeoutId);
    timeoutId = setTimeout(function () {
      console.warn('[SB-LOADING] Auto stop sau 60s');
      stopLoading();
    }, 60000);
  });

  // Nếu code backend/JS khác có bắn event hoàn thành thì tắt loading luôn
  window.addEventListener('SECURITY_BUNDLE:run_scan_done', function () {
    if (timeoutId) clearTimeout(timeoutId);
    stopLoading();
  });

  // Nếu trang reload sau khi scan xong thì cũng trở lại trạng thái bình thường
});
JS_EOF

########################################
# 3) Chèn script run_scan_loading.js vào index.html
########################################
if [ ! -f "$INDEX" ]; then
  echo "[WARN] Không tìm thấy $INDEX – bỏ qua bước hook JS."
else
  echo "[i] Hook run_scan_loading.js vào templates/index.html"
  python3 - "$INDEX" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = '{{ url_for(\'static\', filename=\'run_scan_loading.js\') }}'
if snippet in data:
    print("[INFO] index.html đã include run_scan_loading.js – bỏ qua.")
    sys.exit(0)

insert = '  <script src="' + snippet + '"></script>\n</body>'

if '</body>' not in data:
    print("[WARN] Không thấy </body> trong index.html – không chèn được script.")
else:
    data = data.replace('</body>', insert)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script run_scan_loading.js trước </body>.")
PY
fi

echo "[DONE] patch_ui_fullscreen_and_loading_v1.sh hoàn thành."
