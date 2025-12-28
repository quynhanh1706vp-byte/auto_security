#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/security_resilient.css"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

BKP="$CSS.bak_navfinal_$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "$BKP"
echo "[i] Backup security_resilient.css -> $BKP"

cat >> "$CSS" << 'CSS'


/* ===== NAV COLOR OVERRIDE – FINAL ===== */

/* Bất kỳ nav-item đang active đều nền xanh lá giống Dashboard */
.nav-item.active,
.nav-item.active > a,
.nav-item > a.active {
  background: #80d36b !important;
  border-color: #c5ff9c !important;
  color: #04130a !important;
}

/* Chữ của mọi nav-item (khi không active) là xanh lá nhạt */
.nav-item > a {
  color: #b7f9b7 !important;
}

/* Riêng anchor trỏ tới /settings – đảm bảo luôn chữ xanh, không tím */
a[href="/settings"] {
  color: #b7f9b7 !important;
}
CSS

echo "[OK] Đã append NAV COLOR OVERRIDE – FINAL."
