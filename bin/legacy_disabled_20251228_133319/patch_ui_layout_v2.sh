#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"
JS="$ROOT/static/run_scan_loading.js"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

########################################
# 1) CSS: fullscreen + nav dọc + màu tab
########################################
if grep -q 'SB-UI-V2-FULLSCREEN' "$CSS"; then
  echo "[INFO] CSS đã có block SB-UI-V2-FULLSCREEN – bỏ qua append."
else
  echo "[i] Append CSS SB-UI-V2-FULLSCREEN vào $CSS"
  cat >> "$CSS" <<'CSS_EOF'

/* ==== SB-UI-V2-FULLSCREEN ==== */

html, body {
  height: 100%;
  margin: 0;
  padding: 0;
}

/* Khối nội dung chính rộng hơn, sát 2 bên hơn một chút */
main, .main-container, .page-wrapper, .page-content {
  max-width: 1600px;
  margin: 0 auto;
  padding: 16px 24px 40px 24px;
}

/* Accent chính: dùng lại màu gần giống nút Run (xanh lá) */
:root {
  --sb-accent: #1ed760;
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

/* Tab active */
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

/* Chuyển nav sang dạng dọc */
.nav-item {
  display: block;
  margin: 4px 0;
}

/* Nếu container nav đang flex ngang thì ép nó xếp dọc */
.nav, .top-nav, .nav-container, .header-nav {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

/* Mobile: cho nav full width */
@media (max-width: 900px) {
  .nav, .top-nav, .nav-container, .header-nav {
    align-items: stretch;
  }
}

/* Loading state cho nút Run scan */
.sb-btn-run-loading {
  position: relative;
  opacity: 0.8;
  cursor: wait;
}

/* Spinner nhỏ */
.sb-btn-run-spinner {
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

/* Đẩy chart severity lên cao hơn một chút (best-effort) */
#severity-chart,
#severityChart,
#severity_chart_canvas {
  margin-top: 16px;
  order: -1;
}

/* Layout grid cho card + chart */
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
fi

########################################
# 2) JS: trạng thái loading nút Run scan
########################################
echo "[i] Ghi JS vào $JS"
cat > "$JS" <<'JS_EOF';
document.addEventListener('DOMContentLoaded', function () {
  function findRunButton() {
    // Ưu tiên id cố định nếu có
    var btn = document.getElementById('btn-run-scan');
    if (btn) return btn;

    // Thử tìm theo text "Run scan"
    var candidates = document.querySelectorAll('button, a');
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i];
      var text = (c.textContent || '').trim().toLowerCase();
      if (text === 'run scan' || text.indexOf('run scan') === 0) {
        return c;
      }
    }
    return null;
  }

  var btn = findRunButton();
  if (!btn) {
    console.warn('[SB-LOADING] Không tìm thấy nút Run scan.');
    return;
  }

  console.log('[SB-LOADING] Gắn loading cho nút:', btn);

  var originalHtml = btn.innerHTML;
  var timeoutId = null;

  function startLoading() {
    if (btn.classList.contains('sb-btn-run-loading')) return;
    btn.classList.add('sb-btn-run-loading');
    btn.disabled = true;
    btn.innerHTML =
      '<span class="sb-btn-run-spinner"></span>' +
      '<span>Đang chạy scan…</span>';
  }

  function stopLoading() {
    btn.classList.remove('sb-btn-run-loading');
    btn.disabled = false;
    btn.innerHTML = originalHtml;
  }

  btn.addEventListener('click', function () {
    startLoading();
    if (timeoutId) clearTimeout(timeoutId);
    timeoutId = setTimeout(function () {
      console.warn('[SB-LOADING] Auto stop sau 60s');
      stopLoading();
    }, 60000);
  });

  // Cho phép backend/JS khác tắt loading khi scan xong
  window.addEventListener('SECURITY_BUNDLE:run_scan_done', function () {
    if (timeoutId) clearTimeout(timeoutId);
    stopLoading();
  });
});
JS_EOF

########################################
# 3) Hook JS vào các template chính
########################################
for TPL in "$ROOT/templates/index.html" "$ROOT/templates/base.html"; do
  if [ -f "$TPL" ]; then
    echo "[i] Hook run_scan_loading.js vào $TPL"
    python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "run_scan_loading.js" in data:
    print("[INFO] Đã include run_scan_loading.js – bỏ qua.")
else:
    insert = "  <script src=\"{{ url_for('static', filename='run_scan_loading.js') }}\"></script>\\n</body>"
    if "</body>" in data:
        data = data.replace("</body>", insert)
        path.write_text(data, encoding="utf-8")
        print("[OK] Đã chèn script trước </body>.")
    else:
        print("[WARN] Không thấy </body> trong", path)
PY
  else
    echo "[WARN] Không tìm thấy $TPL – bỏ qua."
  fi
done

echo "[DONE] patch_ui_layout_v2.sh hoàn thành."
