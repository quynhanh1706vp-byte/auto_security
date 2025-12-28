#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
CFG="$ROOT/tool_config.json"
STATIC_CFG="$ROOT/static/tool_config.json"

echo "[i] ROOT = $ROOT"
echo "[i] CFG  = $CFG"
echo "[i] OUT  = $STATIC_CFG"

if [ ! -f "$CFG" ]; then
  echo "[ERR] Không tìm thấy $CFG"
  exit 1
fi

cp "$CFG" "$STATIC_CFG"
echo "[DONE] Đã copy tool_config.json -> static/tool_config.json"
