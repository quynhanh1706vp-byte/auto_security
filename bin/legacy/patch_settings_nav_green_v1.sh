#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/security_resilient.css"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

BKP="$CSS.bak_$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "$BKP"
echo "[i] Backup CSS cũ -> $BKP"

cat >> "$CSS" << 'CSS'


/* === OVERRIDE: Settings nav item dùng màu xanh lá giống Dashboard / Run === */
.nav-item a[href="/settings"],
.nav-item a[href="/settings"]:hover,
.nav-item a[href="/settings"].active {
  background: linear-gradient(90deg, #28a745, #22c55e);
  border-color: #22c55e;
  color: #f8fafc;
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.35);
}
CSS

echo "[OK] Đã append override: Settings nav = màu xanh lá."
