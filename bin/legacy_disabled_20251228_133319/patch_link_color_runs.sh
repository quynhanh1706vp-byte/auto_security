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

# Nếu đã patch rồi thì bỏ qua
if grep -q 'SB-LINK-RUNS-COLOR' "$CSS"; then
  echo "[INFO] Đã có block SB-LINK-RUNS-COLOR trong CSS, không thêm nữa."
  exit 0
fi

cat >> "$CSS" <<'CSS'

/* SB-LINK-RUNS-COLOR */
/* Link trong phần nội dung chính (bao gồm "Open report") dùng màu xanh lá đồng bộ UI */
.sb-main a,
.sb-main a:visited,
.sb-card-runs a,
.sb-card-runs a:visited {
  color: #7fe686;
  text-decoration: none;
  font-weight: 500;
}

.sb-main a:hover,
.sb-card-runs a:hover {
  color: #b8ffbf;
  text-decoration: underline;
}
CSS

echo "[DONE] Đã patch màu link cho Open report & các link trong nội dung."
