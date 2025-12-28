#!/usr/bin/env bash
set -euo pipefail

echo "[i] Đổi 'Scan PROJECT' -> 'RULE overrides' trong templates/*.html"

python3 - <<'PY'
from pathlib import Path

root = Path("templates")
count = 0
for path in root.rglob("*.html"):
    text = path.read_text(encoding="utf-8")
    if "Scan PROJECT" in text:
        new = text.replace("Scan PROJECT", "RULE overrides")
        path.write_text(new, encoding="utf-8")
        print("[OK] Patched:", path)
        count += 1

if count == 0:
    print("[WARN] Không tìm thấy 'Scan PROJECT' trong templates – có thể text đã đổi trước đó.")
else:
    print(f"[DONE] Đã đổi trong {count} file.")
PY

echo "[DONE] patch_nav_scan_to_rule_overrides_v2.sh hoàn thành."
