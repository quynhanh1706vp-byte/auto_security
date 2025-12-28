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
if grep -q 'SB-SIDEBAR-4TABS-COLOR' "$CSS"; then
  echo "[INFO] Đã có block SB-SIDEBAR-4TABS-COLOR trong CSS."
  exit 0
fi

cat >> "$CSS" <<'CSS'

/* SB-SIDEBAR-4TABS-COLOR */
/* Màu riêng cho 4 tab: Dashboard / Run & Report / Settings / Data Source */

/* --- Dashboard --- */
.sb-sidebar .nav-item a[href="/"],
.sb-sidebar .nav-item.active a[href="/"] {
  color: #38bdf8;
}
.sb-sidebar .nav-item a[href="/"].active,
.sb-sidebar .nav-item.active a[href="/"] {
  background: linear-gradient(135deg,#0ea5e9,#38bdf8);
  color: #020617;
  font-weight: 600;
}

/* --- Run & Report --- */
.sb-sidebar .nav-item a[href="/runs"],
.sb-sidebar .nav-item.active a[href="/runs"] {
  color: #4ade80;
}
.sb-sidebar .nav-item a[href="/runs"].active,
.sb-sidebar .nav-item.active a[href="/runs"] {
  background: linear-gradient(135deg,#16a34a,#4ade80);
  color: #020617;
  font-weight: 600;
}

/* --- Settings --- */
.sb-sidebar .nav-item a[href="/settings"],
.sb-sidebar .nav-item.active a[href="/settings"] {
  color: #facc15;
}
.sb-sidebar .nav-item a[href="/settings"].active,
.sb-sidebar .nav-item.active a[href="/settings"] {
  background: linear-gradient(135deg,#eab308,#facc15);
  color: #020617;
  font-weight: 600;
}

/* --- Data Source --- */
.sb-sidebar .nav-item a[href="/data_source"],
.sb-sidebar .nav-item.active a[href="/data_source"] {
  color: #a855f7;
}
.sb-sidebar .nav-item a[href="/data_source"].active,
.sb-sidebar .nav-item.active a[href="/data_source"] {
  background: linear-gradient(135deg,#7c3aed,#a855f7);
  color: #020617;
  font-weight: 600;
}
CSS

echo "[DONE] Đã patch màu cho 4 tab sidebar."
