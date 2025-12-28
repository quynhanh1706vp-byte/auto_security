#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text()

marker = "/* PATCH_SIDEBAR_NAV_ACTIVE_UNIFORM */"
if marker in css:
    print("[OK] Đã có PATCH_SIDEBAR_NAV_ACTIVE_UNIFORM, bỏ qua.")
else:
    snippet = """
/* PATCH_SIDEBAR_NAV_ACTIVE_UNIFORM */
/* Định nghĩa lại style chung cho tất cả nav-item ở sidebar */

/* Style base cho mọi item trong sidebar */
.nav-item a {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 9999px;
  color: #e5e7eb;
  text-decoration: none;
}

/* Hover nhẹ */
.nav-item a:hover {
  background-color: rgba(148, 163, 184, 0.2);
  color: #f9fafb;
}

/* Trạng thái ACTIVE – áp dụng chung cho Dashboard / Runs / Settings / Data Source */
.nav-item.active a {
  background: linear-gradient(90deg, #4f46e5, #22c55e);
  color: #f9fafb !important;
}

/* Chấm trạng thái (nếu có) trên item active */
.nav-item .status-dot {
  background-color: #4b5563;
}
.nav-item.active .status-dot {
  background-color: #a7f3d0;
}
"""
    css = css + "\\n" + snippet + "\\n"
    path.write_text(css)
    print("[OK] Đã append PATCH_SIDEBAR_NAV_ACTIVE_UNIFORM vào CSS.")
PY

echo "[DONE] patch_sidebar_nav_active_uniform.sh hoàn thành."
