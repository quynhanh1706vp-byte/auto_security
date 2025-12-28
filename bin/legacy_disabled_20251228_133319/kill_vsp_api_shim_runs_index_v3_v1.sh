#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_api_shim_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

# Backup trước khi đè
TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$JS.bak_kill_runs_index_$TS"
echo "[BACKUP] $JS -> $JS.bak_kill_runs_index_$TS"

cat > "$JS" << 'JSEND'
// VSP API SHIM – DISABLED
// Bản thương mại 2025 dùng API thật từ Core (8961), không intercept nữa.
(function () {
  console.log("[VSP_API_SHIM] disabled – dùng API runs_index_v3 thật từ Core");
})();
JSEND

echo "[OK] Đã vô hiệu hóa shim trong $JS"
