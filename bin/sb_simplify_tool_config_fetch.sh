#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS="$ROOT/static/sb_fill_tools_from_config.js"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

python3 - "$JS" <<'PY'
import sys, re

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = f.read()
old = data

pattern = r"const CANDIDATE_URLS\s*=\s*\[[^\]]*\];"
replacement = """const CANDIDATE_URLS = [
  "/static/tool_config.json"
];"""

new = re.sub(pattern, replacement, data, count=1, flags=re.DOTALL)

if new == old:
    print("[WARN] Không tìm thấy CANDIDATE_URLS để patch – file có thể đã được chỉnh tay.")
else:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print("[OK] Đã thu gọn CANDIDATE_URLS còn 1 URL duy nhất: /static/tool_config.json")
PY

echo "[DONE] sb_simplify_tool_config_fetch.sh hoàn thành."
