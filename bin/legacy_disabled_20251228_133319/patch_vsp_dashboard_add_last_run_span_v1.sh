#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

BACKUP="${TPL}.bak_last_run_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - "$TPL" << 'PY'
import sys, re
path = sys.argv[1]
txt = open(path, encoding="utf-8").read()

# Bọc phần phía sau "Last run" vào span id="vsp-kpi-total-last-run"
pattern = r"(Last run)([^<\n]*)"

def repl(m):
    label = m.group(1)
    tail = m.group(2)
    inner = tail.strip()
    if not inner:
        inner = " –"
    return f'{label} <span id="vsp-kpi-total-last-run">{inner}</span>'

new, n = re.subn(pattern, repl, txt, count=1)
print(f"[INFO] replaced {n} occurrence(s) of 'Last run'")
open(path, "w", encoding="utf-8").write(new)
PY
