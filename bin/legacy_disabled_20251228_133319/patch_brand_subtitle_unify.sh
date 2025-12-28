#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/base.html"

echo "[i] BASE = $TPL"

# backup
if [ -f "$TPL" ]; then
  cp "$TPL" "${TPL}.bak_brand_$(date +%Y%m%d_%H%M%S)"
  echo "[OK] Đã backup base.html."
fi

python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Đổi mọi chỗ còn 'Scan Dashboard' thành 'Dashboard & Reports'
if "Scan Dashboard" in data:
    data = data.replace("Scan Dashboard", "Dashboard & Reports")

path.write_text(data, encoding="utf-8")
print("[OK] Đã đổi subtitle brand thành 'Dashboard & Reports'.")
PY
