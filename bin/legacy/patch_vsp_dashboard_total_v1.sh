#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${UI_ROOT}/vsp_demo_app.py"

if [ ! -f "$TARGET" ]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TARGET}.bak_total_${TS}"

cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export UI_ROOT

python3 - << 'PY'
import os
import pathlib

ui_root = pathlib.Path(os.environ["UI_ROOT"])
target = ui_root / "vsp_demo_app.py"

txt = target.read_text(encoding="utf-8")

old = '        "total_findings": summary["summary_all"]["total_findings"],\n'

new = (
'        "total_findings": sum(\n'
'            s.get("count", 0) for s in summary.get("summary_by_severity", {}).values()\n'
'        ),\n'
)

if old not in txt:
    print("[WARN] Không tìm thấy dòng total_findings cũ để thay. Có thể đã patch rồi hoặc khác format.")
else:
    txt = txt.replace(old, new)
    print("[PATCH] Đã thay cách tính total_findings từ summary_by_severity")

target.write_text(txt, encoding="utf-8")
print("[DONE] Đã cập nhật vsp_demo_app.py (total_findings)")
PY
