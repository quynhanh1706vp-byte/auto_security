#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

echo "[i] CSS = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* === PATCH_DASHBOARD_STYLE_FORCE_V2 === */"
if marker in css:
    print("[INFO] CSS đã có PATCH_DASHBOARD_STYLE_FORCE_V2, bỏ qua.")
    raise SystemExit(0)

block = """
/* === PATCH_DASHBOARD_STYLE_FORCE_V2 === */
/* Màu chuẩn xanh + full màn hình + chart cao hơn */

/* Màu xanh chuẩn dùng chung (giống Run scan) */
:root {
  --sb-accent-green: #4ade80;
}

/* Toàn bộ body chiếm full chiều cao, nhìn đỡ "lọt thỏm" */
html, body {
  height: 100%;
}

/* Container chính rộng hơn chút (desktop) */
.main-dashboard-container,
.sb-main-container,
.container,
.container-fluid {
  max-width: 1440px;
  margin-left: auto;
  margin-right: auto;
}

/* NAV TOP: Dashboard / Run & Report / Settings / Data Source
   Ép tab active & hover lấy màu xanh như Run scan */
.nav.nav-pills .nav-link,
ul.nav.nav-pills .nav-link {
  border-radius: 999px !important;
  padding: 6px 18px !important;
  font-weight: 500 !important;
  border: 1px solid transparent;
}

/* Active theo class .active hoặc aria-current="page" */
.nav.nav-pills .nav-link.active,
.nav.nav-pills .nav-link[aria-current="page"],
ul.nav.nav-pills .nav-link.active,
ul.nav.nav-pills .nav-link[aria-current="page"] {
  background-color: var(--sb-accent-green) !important;
  border-color: var(--sb-accent-green) !important;
  color: #020617 !important;
}

/* Hover cũng dùng màu xanh nhạt hơn một chút */
.nav.nav-pills .nav-link:hover,
ul.nav.nav-pills .nav-link:hover {
  background-color: var(--sb-accent-green) !important;
  border-color: var(--sb-accent-green) !important;
  color: #020617 !important;
  opacity: 0.95;
}

/* Nếu nav dùng link thẳng theo URL, vẫn ép thêm cho chắc */
a[href="/"].nav-link,
a[href="/runs"].nav-link,
a[href="/settings"].nav-link,
a[href="/datasource"].nav-link {
  border-radius: 999px !important;
  padding: 6px 18px !important;
  font-weight: 500 !important;
}

a[href="/"].nav-link.active,
a[href="/runs"].nav-link.active,
a[href="/settings"].nav-link.active,
a[href="/datasource"].nav-link.active,
a[href="/"].nav-link[aria-current="page"],
a[href="/runs"].nav-link[aria-current="page"],
a[href="/settings"].nav-link[aria-current="page"],
a[href="/datasource"].nav-link[aria-current="page"] {
  background-color: var(--sb-accent-green) !important;
  border-color: var(--sb-accent-green) !important;
  color: #020617 !important;
}

/* Nút Run scan và các nút primary/success dùng chung palette xanh */
.btn-primary,
.btn-success,
.sb-btn-runscan {
  background-color: var(--sb-accent-green) !important;
  border-color: var(--sb-accent-green) !important;
  color: #020617 !important;
  font-weight: 600;
}

.btn-primary:hover,
.btn-success:hover,
.sb-btn-runscan:hover {
  filter: brightness(1.05);
}

/* Biểu đồ SEVERITY – tăng chiều cao cho toàn bộ ApexCharts */
.apexcharts-canvas,
.apexcharts-svg,
.apexcharts-inner {
  max-height: 260px !important;
}

.apexcharts-canvas svg,
.apexcharts-svg svg {
  height: 260px !important;
}

/* Nếu chart nằm trong card dashboard riêng, ép card đó ít padding hơn */
.dashboard-card .apexcharts-canvas,
.dashboard-card .apexcharts-svg {
  margin-top: 4px !important;
  margin-bottom: 4px !important;
}

/* Màu severity text/badge chuẩn hoá (nếu có dùng class sev-*) */
.sev-critical,
.badge.sev-critical {
  color: #fb7185 !important;
}

.sev-high,
.badge.sev-high {
  color: #f59e0b !important;
}

.sev-medium,
.badge.sev-medium {
  color: #facc15 !important;
}

.sev-low,
.badge.sev-low {
  color: #22c55e !important;
}
"""

css = css.rstrip() + "\\n\\n" + marker + "\\n" + block + "\\n"
path.write_text(css, encoding="utf-8")
print("[OK] Đã append PATCH_DASHBOARD_STYLE_FORCE_V2 vào", path)
PY

echo "[DONE] patch_dashboard_style_force.sh hoàn thành."
