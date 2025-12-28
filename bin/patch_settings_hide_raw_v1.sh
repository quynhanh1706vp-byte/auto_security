#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/settings.html"

echo "[i] ROOT = $ROOT"
cd "$ROOT"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

cp "$TPL" "${TPL}.bak_hide_raw_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup settings.html."

python3 - << 'PY'
from pathlib import Path

path = Path("templates/settings.html")
data = path.read_text(encoding="utf-8")

old = '''    <!-- RAW JSON (DEBUG) -->
    <div class="sb-card">
'''
new = '''    <!-- RAW JSON (DEBUG) – hidden for end users -->
    <div class="sb-card" id="tool-config-raw-card" style="display:none;">
'''

if old not in data:
    print("[WARN] Không tìm thấy block RAW JSON cũ, không thay đổi gì.")
else:
    data = data.replace(old, new, 1)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã ẩn card RAW JSON (DEBUG) trong settings.html.")
PY

echo "[DONE] patch_settings_hide_raw_v1.sh hoàn thành."
