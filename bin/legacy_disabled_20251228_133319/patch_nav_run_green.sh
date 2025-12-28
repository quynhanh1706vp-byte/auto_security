#!/usr/bin/env bash
set -euo pipefail

TPLS=("templates/index.html" "templates/runs.html" "templates/settings.html")

for TPL in "${TPLS[@]}"; do
  echo "[i] TPL = $TPL"
  if [ ! -f "$TPL" ]; then
    echo "[WARN] Không tìm thấy $TPL, bỏ qua."
    continue
  fi

  python3 - "$TPL" <<'PY'
import sys, pathlib

tpl_path = pathlib.Path(sys.argv[1])
html = tpl_path.read_text(encoding="utf-8")

marker = "/* PATCHED_NAV_GREEN_V1 */"
if marker in html:
    print(f"[INFO] {tpl_path} đã có patch NAV_GREEN_V1, bỏ qua.")
    sys.exit(0)

inject = """
  /* PATCHED_NAV_GREEN_V1 */
  .nav-item.active {
    background: linear-gradient(90deg,#22c55e,#16a34a) !important;
    color: #f9fafb !important;
  }
"""

# Nếu template này có nút .scan-btn (Dashboard) thì patch luôn cho nút đó về xanh
if ".scan-btn" in html:
    inject += """
  .scan-btn {
    background: linear-gradient(90deg,#22c55e,#16a34a) !important;
    color: #0b1120 !important;
    box-shadow: 0 12px 30px rgba(34,197,94,0.50) !important;
  }
  .scan-btn:active {
    transform: translateY(1px);
    box-shadow: 0 8px 20px rgba(34,197,94,0.35) !important;
  }
"""

idx = html.find("</style>")
if idx == -1:
    print(f"[ERR] Không tìm thấy </style> trong {tpl_path}")
else:
    new_html = html[:idx] + inject + "\n" + html[idx:]
    tpl_path.write_text(new_html, encoding="utf-8")
    print(f"[OK] Đã patch màu xanh cho {tpl_path}")
PY
done
