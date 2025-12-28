#!/usr/bin/env bash
set -euo pipefail

echo "[i] Đổi mọi 'Scan PROJECT' -> 'Rule overrides' trong templates/*.html"

python3 - <<'PY'
from pathlib import Path

root = Path("templates")
count = 0
for path in root.rglob("*.html"):
    text = path.read_text(encoding="utf-8")
    if "Scan PROJECT" in text:
        new = text.replace("Scan PROJECT", "Rule overrides")
        path.write_text(new, encoding="utf-8")
        print("[OK] Patched:", path)
        count += 1

if count == 0:
    print("[WARN] Không tìm thấy 'Scan PROJECT' trong templates/*.html – có thể text nằm ở chỗ khác.")
else:
    print(f"[DONE] Đã đổi trong {count} file.")
PY

echo "[DONE] patch_nav_scan_to_rule_overrides.sh hoàn thành."
