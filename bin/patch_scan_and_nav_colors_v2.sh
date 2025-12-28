#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

marker = "/* PATCHED_RUN_AND_NAV_COLOR_V2 */"
if marker in html:
    print("[INFO] Đã có block PATCHED_RUN_AND_NAV_COLOR_V2, bỏ qua.")
    sys.exit(0)

inject = """
  /* PATCHED_RUN_AND_NAV_COLOR_V2 */
  .scan-btn {
    background: linear-gradient(90deg,#6366f1,#ec4899) !important;
    color: #f9fafb !important;
    box-shadow: 0 12px 30px rgba(99,102,241,0.45) !important;
  }
  .scan-btn:active {
    transform: translateY(1px);
    box-shadow: 0 8px 20px rgba(99,102,241,0.35) !important;
  }
  .nav-item.active {
    background: linear-gradient(90deg,#6366f1,#ec4899) !important;
    color: #f9fafb !important;
  }
"""

# chèn ngay trước </style> đầu tiên
idx = html.find("</style>")
if idx == -1:
    print("[ERR] Không tìm thấy </style> trong index.html")
    sys.exit(1)

new_html = html[:idx] + inject + "\n" + html[idx:]
path.write_text(new_html, encoding="utf-8")
print("[OK] Đã chèn block PATCHED_RUN_AND_NAV_COLOR_V2 vào templates/index.html")
PY
