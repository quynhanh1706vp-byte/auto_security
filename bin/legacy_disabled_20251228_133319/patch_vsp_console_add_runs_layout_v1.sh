#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH_CONSOLE_RUNS_LAYOUT] Append loader cho vsp_runs_overview_layout_v1.js ..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "${FILE}.bak_runs_layout_${TS}"
echo "[BACKUP] $FILE -> ${FILE}.bak_runs_layout_${TS}"

if grep -q "VSP_RUNS_LAYOUT_HELPER_V1" "$FILE"; then
  echo "[PATCH_CONSOLE_RUNS_LAYOUT] Đã có helper, bỏ qua."
  exit 0
fi

cat >> "$FILE" << 'JS'

/* VSP_RUNS_LAYOUT_HELPER_V1
 * Tự động load vsp_runs_overview_layout_v1.js từ console patch.
 */
(function(){
  try {
    var s = document.createElement('script');
    s.src = '/static/js/vsp_runs_overview_layout_v1.js';
    s.defer = true;
    document.head.appendChild(s);
    console.log('[VSP_RUNS_LAYOUT] helper script injected from console patch.');
  } catch (e) {
    console.warn('[VSP_RUNS_LAYOUT] cannot inject layout script:', e);
  }
})();
JS

echo "[PATCH_CONSOLE_RUNS_LAYOUT] Done."
