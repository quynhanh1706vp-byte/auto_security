#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[i] ROOT = $ROOT"

shopt -s nullglob
changed=0

for TPL in "$ROOT"/templates/*.html; do
  if grep -q "url_for('runs')" "$TPL"; then
    BKP="$TPL.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$TPL" "$BKP"
    echo "[i] Backup $TPL -> $BKP"

    python3 - "$TPL" << 'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
old = data

# đổi mọi chỗ dùng url_for('runs') thành link tĩnh /runs
data = data.replace("{{ url_for('runs') }}", "/runs")

if data != old:
    path.write_text(data, encoding="utf-8")
    print(f"[OK] Patched {path}")
else:
    print(f"[WARN] Không thấy 'url_for('runs')' trong {path} (sau grep?)")
PY

    changed=$((changed+1))
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "[WARN] Không tìm thấy template nào chứa url_for('runs')."
else
  echo "[OK] Đã patch $changed template."
fi
