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
echo "[i] Backup CSS -> $BKP"

cat >> "$CSS" << 'CSS'


/* === OVERRIDE: mọi nav-item đang active dùng màu xanh lá giống Run scan === */
.nav-item.active,
.nav-item.active > a {
  background: linear-gradient(90deg, #28a745, #22c55e);
  border-color: #22c55e;
  color: #f8fafc;
  box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.35);
}
CSS

echo "[OK] Đã append override: .nav-item.active = xanh lá."
