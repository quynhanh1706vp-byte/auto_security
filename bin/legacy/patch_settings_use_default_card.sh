#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/settings.html"
echo "[i] TPL = $TPL"

# backup
if [ -f "$TPL" ]; then
  cp "$TPL" "${TPL}.bak_card_$(date +%Y%m%d_%H%M%S)"
  echo "[OK] Backup settings.html."
fi

python3 - "$TPL" <<'PY'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# 1) bỏ class sb-card-settings, chỉ giữ sb-card
data = data.replace("sb-card sb-card-settings", "sb-card")
data = data.replace("sb-card-settings", "sb-card")

path.write_text(data, encoding="utf-8")
print("[OK] Đã chỉnh card Settings dùng sb-card mặc định.")
PY
