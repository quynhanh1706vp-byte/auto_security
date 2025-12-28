#!/usr/bin/env bash
set -e
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

echo "[i] In ra tất cả dòng trong app.py có chữ 'SETTINGS', 'TOOL CONFIG', 'Tool Config', 'tool_status', 'ENABLE_'..."

grep -n "SETTINGS"     "$APP" || true
grep -n "TOOL CONFIG"  "$APP" || true
grep -n "Tool Config"  "$APP" || true
grep -n "tool_status"  "$APP" || true
grep -n "ENABLE_"      "$APP" || true
