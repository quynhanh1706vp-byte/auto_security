#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/static/js/vsp_ui_extras_v25.js"
LOG_PREFIX="[VSP_V253]"

echo "$LOG_PREFIX ROOT = $ROOT"

if [ ! -f "$JS" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $JS"
  exit 1
fi

BAK="$JS.bak_v252_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BAK"
echo "$LOG_PREFIX [BACKUP] $JS -> $BAK"

python - << 'PY'
from pathlib import Path

path = Path("static/js/vsp_ui_extras_v25.js")
txt = path.read_text(encoding="utf-8")

old = '''  function safeParseJSON(text) {
    try {
      return JSON.parse(text);
    } catch (e) {
      console.warn("[VSP_V252] JSON parse error", e);
      return null;
    }
  }
'''
new = '''  function safeParseJSON(text) {
    try {
      return JSON.parse(text);
    } catch (e) {
      // Payload không phải JSON (YAML / text thuần) thì bỏ qua, không log lỗi.
      return null;
    }
  }
'''

if old not in txt:
    print("[VSP_V253] [WARN] Không tìm thấy block safeParseJSON cũ, không thay được.")
else:
    path.write_text(txt.replace(old, new), encoding="utf-8")
    print("[VSP_V253] Đã sửa safeParseJSON thành bản im lặng khi parse lỗi.")
PY

echo "$LOG_PREFIX Hoàn tất patch V2.5.3 – tắt JSON parse error cho Settings/Rules."
