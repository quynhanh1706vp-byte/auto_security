#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_dashboard_enhance_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

# Backup trước khi sửa
BKP="$JS.bak_charts_hook_fix_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BKP"
echo "[BACKUP] Đã backup $JS -> $BKP"

python - << 'PY'
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
js = root / "static/js" / "vsp_dashboard_enhance_v1.js"

txt = js.read_text(encoding="utf-8")

# Xóa mọi patch cũ (nếu có)
pat = r"// === VSP 2025 PATCH – ensure charts engine is called ===[\\s\\S]*?// === END VSP 2025 PATCH ==="
txt_new = re.sub(pat, "", txt)

patch = r"""
// === VSP 2025 PATCH – ensure charts engine is called ===
;(function () {
  if (typeof window === 'undefined') return;
  if (window.VSP_DASHBOARD_ENHANCE_PATCHED_V3) return;
  window.VSP_DASHBOARD_ENHANCE_PATCHED_V3 = true;

  console.log('[VSP_DASH_PATCH] Patching hydrateDashboard to call charts engine.');

  var oldHydrate = window.hydrateDashboard;
  if (typeof oldHydrate !== 'function') {
    console.warn('[VSP_DASH_PATCH] hydrateDashboard is not a function, skip patch.');
    return;
  }

  window.hydrateDashboard = function patchedHydrateDashboard(data) {
    var res = oldHydrate.apply(this, arguments);
    try {
      if (window.VSP_CHARTS_V2 && typeof window.VSP_CHARTS_V2.updateFromDashboard === 'function') {
        window.VSP_CHARTS_V2.updateFromDashboard(data);
      } else if (window.VSP_CHARTS_V3 && typeof window.VSP_CHARTS_V3.updateFromDashboard === 'function') {
        window.VSP_CHARTS_V3.updateFromDashboard(data);
      } else {
        console.warn('[VSP_DASH_PATCH] No charts_v2/v3 engine found to update.');
      }
    } catch (e) {
      console.error('[VSP_DASH_PATCH] Error calling charts engine:', e);
    }
    return res;
  };
})();
// === END VSP 2025 PATCH ===
"""

js.write_text(txt_new.rstrip() + "\n\n" + patch.lstrip(), encoding="utf-8")
print("[OK] Đã patch", js)
PY
