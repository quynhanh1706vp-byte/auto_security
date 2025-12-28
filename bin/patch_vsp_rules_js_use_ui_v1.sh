#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_rules_js_ui_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_rules_js_ui_${TS}"

python3 - << 'PY'
from pathlib import Path

js = Path("static/js/vsp_console_patch_v1.js")
txt = js.read_text(encoding="utf-8")

old = "/api/vsp/rule_overrides_v1"
new = "/api/vsp/rule_overrides_ui_v1"

if old not in txt:
    print("[WARN] Không tìm thấy", old, "trong JS – có thể đã được đổi trước đó.")
else:
    txt = txt.replace(old, new)
    js.write_text(txt, encoding="utf-8")
    print("[OK] Đã thay", old, "->", new, "trong JS.")
PY
