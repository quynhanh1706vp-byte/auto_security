#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

CSS="static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
echo "[i] CSS  = $CSS"

if grep -q 'SB_GLOBAL_FLAT_FULL_OVERRIDE' "$CSS"; then
  echo "[OK] CSS đã có block SB_GLOBAL_FLAT_FULL_OVERRIDE, bỏ qua."
  exit 0
fi

cat >> "$CSS" <<'CSS'

/* =======================================================================
 * SB_GLOBAL_FLAT_FULL_OVERRIDE
 * - Bỏ toàn bộ bo tròn (border-radius:0)
 * - Ép layout chính full width / full screen cho Dashboard, Runs, Settings, Data Source
 * ======================================================================= */

html, body {
  width: 100%;
  height: 100%;
}

body {
  min-height: 100vh;
}

/* 1) Bỏ ROUNDED CHO TOÀN BỘ UI */
* {
  border-radius: 0 !important;
}

/* 2) Các khối layout chính luôn full chiều ngang */
.sb-page,
.sb-layout,
.sb-main-wrapper,
.sb-dashboard-main,
.sb-runs-main,
.sb-settings-main,
.sb-datasource-main {
  width: 100%;
  max-width: 100%;
}

/* 3) Card / panel / box chính – kéo full theo chiều ngang container */
.sb-card,
.sb-panel,
.sb-section,
.sb-box,
.sb-kpi,
.sb-run-row,
.sb-datasource-card {
  width: 100%;
  max-width: 100%;
}

/* 4) Hạn chế việc template cũ giới hạn max-width / margin auto */
.sb-card,
.sb-panel,
.sb-section,
.sb-datasource-card {
  margin-left: 0;
  margin-right: 0;
}

/* 5) Nút, input… đồng bộ flat style (dạng kỹ thuật, không bo) */
button,
input,
select,
textarea,
.sb-nav-link,
.sb-pill {
  border-radius: 0 !important;
}
CSS

echo "[OK] Đã append block SB_GLOBAL_FLAT_FULL_OVERRIDE vào $CSS."
