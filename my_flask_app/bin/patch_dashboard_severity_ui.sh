#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy file $HTML trong thư mục hiện tại."
  exit 1
fi

python3 - <<'PY' "$HTML"
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

changed = False

# Đổi wording cho đúng 6 mức: INFO / TRACE
if "INFO + TRACE" in text:
    text = text.replace("INFO + TRACE", "INFO / TRACE")
    changed = True

# Mô tả rõ ràng hơn cho INFO / TRACE
old_sub = "Informational checks, debug / trace-only rules."
new_sub = "Informational checks (INFO) and trace-only rules (TRACE)."
if old_sub in text:
    text = text.replace(old_sub, new_sub)
    changed = True

if not changed:
    print("[WARN] Không tìm thấy chuỗi cần sửa trong HTML – không có thay đổi.")
else:
    path.write_text(text, encoding="utf-8")
    print(f"[OK] Đã cập nhật wording severity INFO / TRACE trong {path}")
PY
