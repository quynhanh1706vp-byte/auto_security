#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/security_resilient.css"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

BKP="$CSS.bak_force_$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "$BKP"
echo "[i] Backup security_resilient.css -> $BKP"

cat >> "$CSS" << 'CSS'


/* === FORCE: riêng tab Settings luôn dùng màu xanh lá giống Dashboard / Run === */
.sidebar .nav-item a[href="/settings"],
.sidebar .nav-item a[href="/settings"]:hover,
.sidebar .nav-item a[href="/settings"].active {
  background: linear-gradient(90deg, #28a745, #22c55e) !important;
  border-color: #22c55e !important;
  color: #f8fafc !important;
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.35) !important;
}
CSS

echo "[OK] Đã append rule FORCE cho tab Settings (xanh lá)."
