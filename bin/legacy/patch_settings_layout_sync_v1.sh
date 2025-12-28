#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/settings.html"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"

# 1) Thêm class sb-main-settings cho trang Settings
cd "$ROOT"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

cp "$TPL" "${TPL}.bak_layout_sync_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup settings.html."

python3 - << 'PY'
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

# Thêm class sb-main-settings cho div sb-main đầu tiên
old = '<div class="sb-main">'
new = '<div class="sb-main sb-main-settings">'
if old in data and "sb-main-settings" not in data:
    data = data.replace(old, new, 1)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã thêm class sb-main-settings cho Settings.")
else:
    print("[INFO] sb-main-settings đã tồn tại hoặc không tìm thấy pattern.")
PY

# 2) Thêm CSS cho sb-main-settings để đồng bộ layout
if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

cp "$CSS" "${CSS}.bak_layout_sync_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup security_resilient.css."

python3 - << 'PY'
from pathlib import Path

path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

if ".sb-main-settings" in css:
    print("[INFO] CSS .sb-main-settings đã tồn tại, bỏ qua append.")
else:
    block = """

/* ========== SETTINGS PAGE LAYOUT – ALIGN WITH OTHER TABS ========== */
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

/* Bảng BY TOOL / CONFIG dùng style riêng nhưng đồng bộ card */
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
    css = css.rstrip() + block + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block CSS .sb-main-settings vào security_resilient.css.")
PY

echo "[DONE] patch_settings_layout_sync_v1.sh hoàn thành."
