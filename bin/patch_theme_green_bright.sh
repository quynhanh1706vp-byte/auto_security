#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

echo "[i] Thêm override màu xanh lá sáng vào $CSS"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [theme_green_bright_v1] */"
if marker in css:
    print("[i] Đã có block theme_green_bright_v1, bỏ qua.")
else:
    extra = """
/* [theme_green_bright_v1] – override theme sang xanh lá sáng */
:root {
  --sb-accent: #7CFC00;           /* lime green */
  --sb-accent-soft: rgba(124,252,0,0.18);
  --sb-accent-soft-strong: rgba(124,252,0,0.28);
}

/* Nền tổng thể hơi sáng hơn, vẫn giữ kiểu nền hiện tại nhưng ngả xanh */
body {
  background: radial-gradient(circle at top, #0f2310 0%, #040909 55%, #020406 100%) !important;
}

/* Card chính */
.sb-card, .card {
  border-color: rgba(124,252,0,0.35) !important;
  box-shadow: 0 0 18px rgba(124,252,0,0.15) !important;
}

/* Header các card / title con */
.sb-card h2, .sb-card-title, .sb-section-title {
  color: #e8ffe0 !important;
}

/* KPI (TOTAL FINDINGS, CRITICAL, HIGH, MEDIUM, LOW) */
.kpi-card, .kpi, .sb-kpi-card {
  border-color: rgba(124,252,0,0.35) !important;
  background: linear-gradient(135deg, rgba(124,252,0,0.16), rgba(0,0,0,0.2)) !important;
}

/* Nút chính (Run scan, Run project, v.v.) */
button, .btn, .sb-btn, .sb-btn-primary, .run-btn, .run-button {
  background: var(--sb-accent) !important;
  border-color: var(--sb-accent) !important;
  color: #021104 !important;
}

/* Sidebar – nav item active */
.sidebar .nav-item.active,
.sidebar .nav-item.active a,
.nav-item.active,
.nav-item.active a {
  background: var(--sb-accent) !important;
  color: #021104 !important;
}

/* Sidebar hover */
.sidebar .nav-item a:hover,
.nav-item a:hover {
  background: var(--sb-accent-soft) !important;
}

/* Các thanh nhỏ (progress / severity bar cũ) */
.progress-bar,
.severity-bar,
.sb-mini-bar {
  background: var(--sb-accent) !important;
}

/* Link RUN_xxx trong Trend – Last runs: highlight xanh */
a.run-link, .trend-table a {
  color: #9dff6a !important;
}
"""
    css = css.rstrip() + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block theme_green_bright_v1 vào", path)
PY

echo "[DONE] patch_theme_green_bright.sh hoàn thành."
