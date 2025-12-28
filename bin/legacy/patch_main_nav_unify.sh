#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"
JS="$ROOT/static/patch_main_nav_unify.js"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"
echo "[i] JS   = $JS"
echo "[i] BASE = $BASE"

if [ ! -f "$CSS" ] || [ ! -f "$BASE" ]; then
  echo "[ERR] Thiếu file CSS hoặc base.html"
  exit 1
fi

########################################
# 1) Viết JS: tự set active cho 4 tab
########################################
cat > "$JS" <<'JS'
document.addEventListener('DOMContentLoaded', function () {
  var path = window.location.pathname || '/';
  var routes = ['/', '/runs', '/settings', '/data_source'];

  routes.forEach(function (href) {
    document.querySelectorAll('a[href="' + href + '"]').forEach(function (a) {
      a.classList.add('sb-main-nav-link');
      // active đúng 1 tab theo URL
      if (path === href) {
        a.classList.add('is-active');
      } else if (path === '/' && href === '/') {
        a.classList.add('is-active');
      } else {
        a.classList.remove('is-active');
      }
    });
  });
});
JS

########################################
# 2) Thêm CSS cho 4 tab (đồng bộ)
########################################
if ! grep -q 'SB-MAIN-NAV-UNIFY' "$CSS"; then
  cat >> "$CSS" <<'CSS'

/* SB-MAIN-NAV-UNIFY */
/* Style chung cho 4 tab sidebar: Dashboard / Run & Report / Settings / Data Source */

.sb-main-nav-link {
  display: block;
  padding: 8px 18px;
  margin: 2px 0;
  border-radius: 999px;
  font-size: 14px;
  color: #e5e7eb;
}

/* Đè background cũ của .nav-item.active nếu có */
.nav-item.active a {
  background: transparent !important;
}

/* Tab đang active: nền xanh lá giống phong cách Run & Report */
.sb-main-nav-link.is-active {
  background: linear-gradient(135deg, #16a34a, #4ade80);
  color: #020617;
  font-weight: 600;
}
CSS
else
  echo "[INFO] CSS đã có block SB-MAIN-NAV-UNIFY."
fi

########################################
# 3) Nhúng script vào base.html (dùng cho mọi page)
########################################
if ! grep -q 'patch_main_nav_unify.js' "$BASE"; then
  python3 - "$BASE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

marker = "</body>"
snippet = '    <script src="{{ url_for(\'static\', filename=\'patch_main_nav_unify.js\') }}"></script>\\n'

if "patch_main_nav_unify.js" in data:
    sys.exit(0)

if marker not in data:
    print("[WARN] Không tìm thấy </body> trong base.html, bỏ qua.")
    sys.exit(0)

data = data.replace(marker, snippet + marker)
path.write_text(data, encoding="utf-8")
print("[OK] Đã chèn script patch_main_nav_unify.js vào base.html")
PY
else
  echo "[INFO] base.html đã nhúng patch_main_nav_unify.js."
fi

echo "[DONE] patch_main_nav_unify.sh hoàn thành."
