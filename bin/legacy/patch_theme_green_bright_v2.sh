#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

echo "[i] Thêm override theme xanh lá sáng vào $CSS"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [theme_green_bright_v2] */"
if marker in css:
    print("[i] Đã có block theme_green_bright_v2, bỏ qua.")
else:
    extra = """
/* [theme_green_bright_v2] – override toàn bộ theme sang xanh lá sáng */
:root {
  --sb-accent: #7CFC00;                   /* lime green sáng */
  --sb-accent-soft: rgba(124,252,0,0.18);
  --sb-accent-soft-strong: rgba(124,252,0,0.30);
}

/* Nền tổng thể (mọi trang, kể cả Settings) */
body {
  background: radial-gradient(circle at top, #122515 0%, #050a06 55%, #020405 100%) !important;
}

/* Card chung */
.sb-card, .card {
  border-color: rgba(124,252,0,0.35) !important;
  box-shadow: 0 0 18px rgba(124,252,0,0.18) !important;
}

/* Title / heading trong card */
.sb-card h2,
.sb-card-title,
.sb-section-title,
.sb-main-title {
  color: #e9ffe5 !important;
}

/* Sub-title / text nhấn */
.sb-main-subtitle {
  color: #c8ffd0 !important;
}

/* KPI (TOTAL, CRIT, HIGH, MEDIUM, LOW) */
.kpi-card, .kpi, .sb-kpi-card {
  border-color: rgba(124,252,0,0.35) !important;
  background: linear-gradient(135deg,
              rgba(124,252,0,0.18),
              rgba(0,0,0,0.18)) !important;
}

/* Nút chính (Run scan, Run project, Save...) */
button,
.btn,
.sb-btn,
.sb-btn-primary,
.run-btn,
.run-button {
  background: var(--sb-accent) !important;
  border-color: var(--sb-accent) !important;
  color: #021004 !important;
}

/* Sidebar nav */
.sidebar .nav-item,
.nav-item {
  border-radius: 8px;
}

.sidebar .nav-item.active,
.sidebar .nav-item.active a,
.nav-item.active,
.nav-item.active a {
  background: var(--sb-accent) !important;
  color: #021004 !important;
}

.sidebar .nav-item a,
.nav-item a {
  color: #bdfcaf !important;
}

.sidebar .nav-item a:hover,
.nav-item a:hover {
  background: var(--sb-accent-soft) !important;
}

/* Thanh progress / severity bar cũ */
.progress-bar,
.severity-bar,
.sb-mini-bar {
  background: var(--sb-accent) !important;
}

/* Link xanh */
a, a:visited {
  color: #9dff6a !important;
}
"""
    css = css.rstrip() + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block theme_green_bright_v2 vào", path)
PY

echo "[DONE] patch_theme_green_bright_v2.sh hoàn thành."
