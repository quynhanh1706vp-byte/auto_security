#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CSS="$ROOT/static/css/security_resilient.css"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS" >&2
  exit 1
fi

cp "$CSS" "${CSS}.bak_settings_table_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup security_resilient.css."

python3 - << 'PY'
from pathlib import Path

path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

if ".sb-table-settings" in css:
    print("[INFO] Đã có block .sb-table-settings, không append nữa.")
else:
    block = """

/* ========== SETTINGS – TOOL CONFIG TABLE ========== */
.sb-table-settings {
  font-size: 13px;
}

.sb-table-settings th,
.sb-table-settings td {
  padding: 6px 10px;
}

.sb-table-settings th {
  text-transform: uppercase;
  letter-spacing: .04em;
  font-size: 11px;
}

/* Tool */
.sb-table-settings td:nth-child(1) {
  width: 120px;
  white-space: nowrap;
}

/* Enabled / Level / Modes */
.sb-table-settings td:nth-child(2),
.sb-table-settings td:nth-child(3),
.sb-table-settings td:nth-child(4) {
  width: 90px;
  text-align: center;
  white-space: nowrap;
}

/* Notes – dài, rút gọn với ellipsis */
.sb-table-settings td:nth-child(5) {
  max-width: 650px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Zebra nhẹ cho dễ đọc */
.sb-table-settings tbody tr:nth-child(even) {
  background-color: rgba(255, 255, 255, 0.02);
}
"""
    css = css.rstrip() + block + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block .sb-table-settings vào security_resilient.css.")
PY

echo "[DONE] patch_settings_table_css_v1.sh hoàn thành."
