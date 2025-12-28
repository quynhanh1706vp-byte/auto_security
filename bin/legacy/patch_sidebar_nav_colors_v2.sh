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

marker = "/* PATCH_SIDEBAR_NAV_COLORS_V2 */"
if marker in css:
    print("[OK] Đã có PATCH_SIDEBAR_NAV_COLORS_V2, bỏ qua.")
else:
    snippet = """
/* PATCH_SIDEBAR_NAV_COLORS_V2 */
/* Đồng bộ màu cho các menu sidebar Dashboard / Run & Report / Settings / Data Source */

/* Bo tròn cho tất cả item sidebar chính */
nav a[href="/"],
nav a[href="/runs"],
nav a[href="/settings"],
nav a[href="/data_source"],
nav a[href="/data-source"] {
  border-radius: 9999px;
}

/* Trạng thái ACTIVE – nền xanh tím + chữ trắng giống Dashboard */
nav a[href="/"].active,
nav a[href="/runs"].active,
nav a[href="/settings"].active,
nav a[href="/data_source"].active,
nav a[href="/data-source"].active {
  background: linear-gradient(90deg, #4f46e5, #6366f1);
  color: #f9fafb !important;
}

/* Text bình thường trong sidebar */
nav a[href="/"],
nav a[href="/runs"],
nav a[href="/settings"],
nav a[href="/data_source"],
nav a[href="/data-source"] {
  color: #e5e7eb;
}

/* Hover cho sidebar */
nav a[href="/"]:hover,
nav a[href="/runs"]:hover,
nav a[href="/settings"]:hover,
nav a[href="/data_source"]:hover,
nav a[href="/data-source"]:hover {
  color: #f9fafb;
}

/* Nếu có chấm trạng thái trong item active (class status-dot) thì tô màu xanh mint */
.status-dot {
  background-color: #4b5563; /* mặc định xám */
}
nav a[href="/"].active .status-dot,
nav a[href="/runs"].active .status-dot,
nav a[href="/settings"].active .status-dot,
nav a[href="/data_source"].active .status-dot,
nav a[href="/data-source"].active .status-dot {
  background-color: #a7f3d0;
}
"""
    css = css + "\n" + snippet + "\n"
    path.write_text(css)
    print("[OK] Đã append PATCH_SIDEBAR_NAV_COLORS_V2 vào CSS.")
PY

echo "[DONE] patch_sidebar_nav_colors_v2.sh hoàn thành."
