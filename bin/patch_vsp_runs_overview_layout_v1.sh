#!/usr/bin/env bash
set -euo pipefail

echo "[PATCH_RUNS_LAYOUT] Bắt đầu patch template để load CSS/JS Runs overview..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"

CANDIDATES=(
  "$UI_ROOT/templates/vsp_5tabs_full.html"
  "$UI_ROOT/templates/vsp_dashboard_2025.html"
)

FOUND=""

for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ] && grep -q "Runs overview" "$f"; then
    FOUND="$f"
    break
  fi
done

if [ -z "$FOUND" ]; then
  echo "[PATCH_RUNS_LAYOUT][ERR] Không tìm thấy template chứa 'Runs overview'."
  exit 1
fi

TPL="$FOUND"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TPL}.bak_runs_layout_${TS}"
cp "$TPL" "$BACKUP"
echo "[PATCH_RUNS_LAYOUT] Backup: $TPL -> $BACKUP"

export TPL

python - << 'PY'
import os, pathlib

tpl_path = pathlib.Path(os.environ["TPL"])
txt = tpl_path.read_text(encoding="utf-8")
lower = txt.lower()
changed = False

# 1) Inject CSS vsp_charts_2025.css vào <head> nếu chưa có
if "vsp_charts_2025.css" not in txt:
    pos = lower.find("</head>")
    if pos != -1:
        link = '  <link rel="stylesheet" href="/static/css/vsp_charts_2025.css">\n'
        txt = txt[:pos] + link + txt[pos:]
        lower = txt.lower()
        print("[PATCH_RUNS_LAYOUT] Đã inject link CSS vsp_charts_2025.css.")
        changed = True

# 2) Inject JS vsp_runs_overview_layout_v1.js trước </body> nếu chưa có
if "vsp_runs_overview_layout_v1.js" not in txt:
    pos = lower.rfind("</body>")
    if pos != -1:
        script = '  <script src="/static/js/vsp_runs_overview_layout_v1.js"></script>\n'
        txt = txt[:pos] + script + txt[pos:]
        print("[PATCH_RUNS_LAYOUT] Đã inject script vsp_runs_overview_layout_v1.js.")
        changed = True

if changed:
    tpl_path.write_text(txt, encoding="utf-8")
    print("[PATCH_RUNS_LAYOUT] ĐÃ GHI file template mới:", tpl_path)
else:
    print("[PATCH_RUNS_LAYOUT] Không có thay đổi nào (có thể đã patch trước đó).")
PY

echo "[PATCH_RUNS_LAYOUT] Done."
