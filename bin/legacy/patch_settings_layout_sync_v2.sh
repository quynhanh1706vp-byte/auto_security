#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/settings.html"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"

# --- 1) Patch settings.html ---
cd "$ROOT"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

cp "$TPL" "${TPL}.bak_layout_sync_v2_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup settings.html."

python3 - << 'PY'
import re
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

# a) Thêm sb-main-settings vào div sb-main đầu tiên (dùng regex cho chắc)
new_data, n = re.subn(
    r'<div class="sb-main([^"]*)">',
    r'<div class="sb-main sb-main-settings\1">',
    data,
    count=1,
)
if n:
    data = new_data
    print(f"[OK] Đã thêm sb-main-settings cho sb-main (match={n}).")
else:
    print("[WARN] Không tìm thấy div.sb-main để thêm sb-main-settings.")

# b) Đảm bảo bảng có class sb-table-settings
if "sb-table-settings" not in data:
    data = data.replace(
        "sb-table sb-table-compact",
        "sb-table sb-table-compact sb-table-settings",
        1,
    )
    print("[OK] Đã thêm sb-table-settings cho bảng.")
else:
    print("[INFO] settings.html đã có sb-table-settings.")

path.write_text(data, encoding="utf-8")
PY

# --- 2) Patch CSS ---
if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

cp "$CSS" "${CSS}.bak_layout_sync_v2_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup security_resilient.css."

python3 - << 'PY'
from pathlib import Path

path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

block = """

/* ========== SETTINGS PAGE LAYOUT – v2 ========== */
.sb-main-settings .sb-main-header {
  margin-bottom: 18px;
}

.sb-main-settings .sb-main-title {
  font-size: 20px;
  letter-spacing: .06em;
}

.sb-main-settings .sb-main-subtitle {
  font-size: 13px;
  opacity: .8;
}

.sb-main-settings .sb-card {
  max-width: 1200px;
  margin: 0 auto 24px;
}

/* Bảng BY TOOL / CONFIG – đồng bộ với bảng ở các tab khác */
.sb-main-settings .sb-table-settings {
  width: 100%;
  font-size: 13px;
}

.sb-main-settings .sb-table-settings th,
.sb-main-settings .sb-table-settings td {
  padding: 6px 10px;
}

.sb-main-settings .sb-table-settings th {
  text-transform: uppercase;
  letter-spacing: .04em;
  font-size: 11px;
}

/* Tool */
.sb-main-settings .sb-table-settings td:nth-child(1) {
  width: 120px;
  white-space: nowrap;
}

/* Enabled / Level / Modes */
.sb-main-settings .sb-table-settings td:nth-child(2),
.sb-main-settings .sb-table-settings td:nth-child(3),
.sb-main-settings .sb-table-settings td:nth-child(4) {
  width: 90px;
  text-align: center;
  white-space: nowrap;
}

/* Notes – dài, rút gọn với ellipsis */
.sb-main-settings .sb-table-settings td:nth-child(5) {
  max-width: 650px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Zebra nhẹ cho dễ đọc */
.sb-main-settings .sb-table-settings tbody tr:nth-child(even) {
  background-color: rgba(255, 255, 255, 0.02);
}
"""

if "SETTINGS PAGE LAYOUT – v2" in css:
  print("[INFO] Block SETTINGS PAGE LAYOUT – v2 đã có, không append.")
else:
  css = css.rstrip() + block + "\n"
  path.write_text(css, encoding="utf-8")
  print("[OK] Đã append block CSS SETTINGS PAGE LAYOUT – v2.")
PY

echo "[DONE] patch_settings_layout_sync_v2.sh hoàn thành."
