#!/usr/bin/env bash
set -euo pipefail

FILE="vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE trong thư mục hiện tại."
  exit 1
fi

echo "[i] Backup file gốc..."
cp "$FILE" "${FILE}.bak_runroot_$(date +%Y%m%d_%H%M%S)"

echo "[i] Append fallback RUN_ROOT vào cuối file..."

cat >> "$FILE" << 'PYEOF'

# ======= Fallback RUN_ROOT (AUTO PATCH) =======
# Nếu trong file chưa có RUN_ROOT, đoạn này sẽ tạo RUN_ROOT trỏ vào thư mục out/
try:
    RUN_ROOT  # type: ignore[name-defined]
except NameError:
    from pathlib import Path as _PathForRunRoot
    RUN_ROOT = _PathForRunRoot("/home/test/Data/SECURITY_BUNDLE/out")
# ======= END Fallback RUN_ROOT =======

PYEOF

echo "[OK] Đã append fallback RUN_ROOT vào vsp_demo_app.py"
