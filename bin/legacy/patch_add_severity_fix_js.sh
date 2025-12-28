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

if "sb_fix_severity_buckets.js" in data:
    print("[INFO] index.html đã có script sb_fix_severity_buckets.js, bỏ qua.")
else:
    marker = "</body>"
    snippet = '  <script src="/static/js/sb_fix_severity_buckets.js?v=20251125"></script>\\n</body>'
    if marker not in data:
        raise SystemExit("[ERR] Không tìm thấy </body> trong templates/index.html")
    data = data.replace(marker, snippet)
    tpl.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn script sb_fix_severity_buckets.js vào index.html")
PY
