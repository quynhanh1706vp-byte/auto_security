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
if grep -q 'SB-LINK-GLOBAL-ANCHOR' "$CSS"; then
  echo "[INFO] Đã có block SB-LINK-GLOBAL-ANCHOR trong CSS."
  exit 0
fi

cat >> "$CSS" <<'CSS'

/* SB-LINK-GLOBAL-ANCHOR */
/* Đổi màu toàn bộ link (Open report, ... ) cho đồng bộ với theme */
a,
a:visited {
  color: #7fe686 !important;  /* xanh lá cùng tông nút Run & Report */
  text-decoration: none;
  font-weight: 500;
}

a:hover {
  color: #b8ffbf !important;
  text-decoration: underline;
}
CSS

echo "[DONE] Đã patch màu link toàn trang."
