#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TPL="templates/index.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - << 'PY'
from pathlib import Path

tpl = Path("templates/index.html")
data = tpl.read_text(encoding="utf-8")

if 'sb_severity_buckets_value' in data:
    print("[INFO] index.html đã có span sb_severity_buckets_value, bỏ qua.")
else:
    target = "0 / 0 / 0 / 0"
    if target not in data:
        raise SystemExit("[ERR] Không tìm thấy chuỗi '0 / 0 / 0 / 0' trong templates/index.html")
    new = '<span id="sb_severity_buckets_value">0 / 0 / 0 / 0</span>'
    data = data.replace(target, new, 1)
    tpl.write_text(data, encoding="utf-8")
    print("[OK] Đã bọc 0 / 0 / 0 / 0 vào span#sb_severity_buckets_value")
PY
