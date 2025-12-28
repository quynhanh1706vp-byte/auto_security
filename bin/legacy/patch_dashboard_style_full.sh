#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

echo "[i] CSS = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* === PATCH_DASHBOARD_STYLE_UNIFY_V1 === */"

if marker in css:
    print("[INFO] CSS đã có PATCH_DASHBOARD_STYLE_UNIFY_V1, bỏ qua append.")
    raise SystemExit(0)

block = r"""
/* === PATCH_DASHBOARD_STYLE_UNIFY_V1 === */
/* Palette & màu chuẩn cho toàn bộ Dashboard */
:root {
  --sb-accent-green: #4ade80;   /* xanh của nút Run scan */
  --sb-sev-critical: #fb7185;   /* đỏ nhạt */
  --sb-sev-high:     #f59e0b;   /* cam */
  --sb-sev-medium:   #facc15;   /* vàng */
  --sb-sev-low:      #22c55e;   /* xanh lá */
}

/* NAV TOP: Dashboard / Run & Report / Settings / Data Source */
.nav-pills .nav-link {
  border-radius: 999px;
  padding: 6px 18px;
  font-weight: 500;
  transition: background-color 0.15s ease, color 0.15s ease;
}

.nav-pills .nav-link.active,
.nav-pills .nav-link:focus,
.nav-pills .nav-link:hover {
  background-color: var(--sb-accent-green);
  color: #020617; /* gần màu nền dark nhưng vẫn đọc rõ */
}

/* Nút Run scan + các nút chính dùng chung 1 màu xanh */
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

/* Màu severity chuẩn hoá, dùng được cho text / badge */
.sev-critical,
.badge.sev-critical {
  color: var(--sb-sev-critical) !important;
}

.sev-high,
.badge.sev-high {
  color: var(--sb-sev-high) !important;
}

.sev-medium,
.badge.sev-medium {
  color: var(--sb-sev-medium) !important;
}

.sev-low,
.badge.sev-low {
  color: var(--sb-sev-low) !important;
}

/* Nếu có badge Bootstrap kiểu bg-* thì override luôn */
.badge.bg-critical,
.badge.bg-danger {
  background-color: var(--sb-sev-critical) !important;
}

.badge.bg-high,
.badge.bg-warning {
  background-color: var(--sb-sev-high) !important;
}

.badge.bg-medium {
  background-color: var(--sb-sev-medium) !important;
}

.badge.bg-low,
.badge.bg-success {
  background-color: var(--sb-sev-low) !important;
}

/* Biểu đồ SEVERITY – đẩy data lên, cao hơn, dễ nhìn */
.dashboard-card canvas,
.dashboard-card .apexcharts-canvas,
#severityChart,
canvas[id*="severity"] {
  max-height: 260px;
  height: 260px !important;
}

/* Đảm bảo container chart không bị padding quá nhiều */
.dashboard-card .chart-container,
.dashboard-card .card-body-chart {
  padding-top: 8px;
  padding-bottom: 8px;
}

/* Full màn hình hơn trên desktop – không quá hẹp */
.main-dashboard-container,
.sb-main-container {
  max-width: 1440px;
  margin: 0 auto;
}

/* Một chút spacing cho section dưới (Trend, By tool/config) */
.section-block + .section-block {
  margin-top: 16px;
}
"""

css = css.rstrip() + "\n\n" + block + "\n"
path.write_text(css, encoding="utf-8")
print("[OK] Đã append block PATCH_DASHBOARD_STYLE_UNIFY_V1 vào", path)
PY

echo "[DONE] patch_dashboard_style_full.sh hoàn thành."
