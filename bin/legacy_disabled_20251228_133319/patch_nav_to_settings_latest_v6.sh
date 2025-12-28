#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL_DIR="$ROOT/templates"

echo "[i] ROOT = $ROOT"
cd "$TPL_DIR"

python3 - << 'PY'
from pathlib import Path

for p in Path(".").glob("*.html"):
    text = p.read_text(encoding="utf-8")
    new = text.replace('href="/settings"', 'href="/settings_latest"')
    if new != text:
        p.write_text(new, encoding="utf-8")
        print(f"[OK] Đã đổi href=/settings -> /settings_latest trong {p}")
PY

echo "[DONE] patch_nav_to_settings_latest_v6.sh hoàn thành."
