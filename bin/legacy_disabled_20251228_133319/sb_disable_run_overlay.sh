#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/run_scan_loading.js"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

python3 - "$JS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
print(f"[i] Patching {path}")

stub = """/* SECURITY_BUNDLE – run_scan_loading.js
 * ĐÃ TẮT overlay 'đang chạy scan' để tránh màn hình đen.
 * Chỉ log debug, không che UI nữa.
 */
document.addEventListener('DOMContentLoaded', function () {
  console.log('[RUN-LOADING] overlay disabled – no-op stub loaded');
});
"""

old = path.read_text(encoding="utf-8")
path.write_text(stub, encoding="utf-8")

print("[OK] Ghi stub run_scan_loading.js – overlay đã bị tắt.")
PY

echo "[DONE] sb_disable_run_overlay.sh hoàn thành."
