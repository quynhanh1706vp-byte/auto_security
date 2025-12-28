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

# Nếu đã patch rồi thì thôi
if grep -q 'SB-SIDEBAR-4TABS-BG-SIMPLE' "$CSS"; then
  echo "[INFO] Đã có block SB-SIDEBAR-4TABS-BG-SIMPLE trong CSS."
  exit 0
fi

cat >> "$CSS" <<'CSS'

/* SB-SIDEBAR-4TABS-BG-SIMPLE */
/* Đổi màu nền cho 4 tab main: Dashboard / Run & Report / Settings / Data Source */
/* Không đổi màu chữ, chỉ chỉnh background khi tab đang active */

.nav-item a {
  border-radius: 999px;
}

/* Dashboard */
.nav-item.active a[href="/"],
.nav-item a[href="/"].active {
  background: linear-gradient(135deg,#0f172a,#1e293b);
}

/* Run & Report */
.nav-item.active a[href="/runs"],
.nav-item a[href="/runs"].active {
  background: linear-gradient(135deg,#14532d,#22c55e);
}

/* Settings */
.nav-item.active a[href="/settings"],
.nav-item a[href="/settings"].active {
  background: linear-gradient(135deg,#433311,#facc15);
}

/* Data Source */
.nav-item.active a[href="/data_source"],
.nav-item a[href="/data_source"].active {
  background: linear-gradient(135deg,#312e81,#a855f7);
}
CSS

echo "[DONE] Đã patch màu nền cho 4 tab sidebar (simple)."
