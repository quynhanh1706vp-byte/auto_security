#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/js/datasource_tool_rules.js"

echo "[i] ROOT = $ROOT"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS" >&2
  exit 1
fi

cp "$JS" "${JS}.bak_fix_url_$(date +%Y%m%d_%H%M%S)" || true
echo "[i] Đã backup datasource_tool_rules.js."

python3 - << 'PY'
from pathlib import Path

path = Path("static/js/datasource_tool_rules.js")
data = path.read_text(encoding="utf-8")
old = data

# Đổi mọi chỗ /api/tool_rules_v2_v2 -> /api/tool_rules_v2
data = data.replace("/api/tool_rules_v2_v2", "/api/tool_rules_v2")
data = data.replace("tool_rules_v2_v2", "tool_rules_v2")  # fallback nếu dùng biến

if data != old:
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã sửa URL tool_rules_v2_v2 -> tool_rules_v2 trong datasource_tool_rules.js.")
else:
    print("[WARN] Không thấy 'tool_rules_v2_v2' trong datasource_tool_rules.js để sửa.")
PY

echo "[DONE] patch_fix_tool_rules_js_url.sh hoàn thành."
