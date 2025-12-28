#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

paths=(
  "$ROOT/static/tool_config.json"
  "$ROOT/static/last_tool_config.json"
)

for f in "${paths[@]}"; do
  if [ -f "$f" ]; then
    echo "[i] Kiểm tra $f"
    first="$(head -c1 "$f" || true)"
    if [ "$first" = "[" ]; then
      # file là list -> backup + reset thành {}
      cp "$f" "${f}.bak_$(date +%Y%m%d_%H%M%S)"
      printf "{}\n" > "$f"
      echo "[OK] $f là list, đã backup và ghi lại thành {}."
    else
      echo "[i] $f có vẻ đã là object (hoặc trống), bỏ qua."
    fi
  else
    echo "[i] Không thấy $f, skip."
  fi
done
