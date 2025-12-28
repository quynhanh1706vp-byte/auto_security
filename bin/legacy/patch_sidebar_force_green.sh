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

marker = "/* PATCH_SIDEBAR_FORCE_GREEN */"
if marker in css:
    print("[OK] Đã có PATCH_SIDEBAR_FORCE_GREEN, bỏ qua.")
else:
    snippet = """
/* PATCH_SIDEBAR_FORCE_GREEN */
/* Ép tất cả nav-item active (Dashboard / Runs / Settings / Data Source) nền xanh như nút Run */

.nav-item > a {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 9999px;
  color: #e5e7eb;
  text-decoration: none;
}

/* Hover nhẹ */
.nav-item > a:hover {
  color: #f9fafb;
  background-color: rgba(148, 163, 184, 0.18);
}

/* BẤT KỲ nav-item nào đang active đều xanh như Run Scan */
.nav-item.active > a {
  background: linear-gradient(90deg, #22c55e, #16a34a) !important;
  color: #f9fafb !important;
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.4);
}

/* Chấm trạng thái nếu có */
.nav-item .status-dot {
  background-color: #4b5563;
}
.nav-item.active .status-dot {
  background-color: #a7f3d0;
}
"""
    css = css + "\\n" + snippet + "\\n"
    path.write_text(css)
    print("[OK] Đã append PATCH_SIDEBAR_FORCE_GREEN vào CSS.")
PY

echo "[DONE] patch_sidebar_force_green.sh hoàn thành."
