#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "[i] ROOT = $ROOT"

shopt -s nullglob
changed=0

for TPL in "$ROOT"/templates/*.html; do
  if grep -q "url_for('runs')" "$TPL" || grep -q "url_for('datasource')" "$TPL"; then
    BKP="$TPL.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$TPL" "$BKP"
    echo "[i] Backup $TPL -> $BKP"

    python3 - "$TPL" << 'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
old = data

# Đổi về link tĩnh cho chắc ăn
data = data.replace("{{ url_for('runs') }}", "/runs")
data = data.replace("{{ url_for('datasource') }}", "/datasource")

if data != old:
    path.write_text(data, encoding="utf-8")
    print(f"[OK] Patched {path}")
else:
    print(f"[WARN] Không có gì thay đổi trong {path}")
PY

    changed += 1
  fi
done

if changed == 0:
  print("[WARN] Không tìm thấy template nào chứa url_for('runs') hoặc url_for('datasource').")
else:
  print(f"[OK] Đã patch {changed} template.")
