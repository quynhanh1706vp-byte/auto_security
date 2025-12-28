#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

# Đổi toàn bộ href="/data_source" thành href="/datasource" trong templates/*
for f in templates/*.html; do
  if grep -q "/data_source" "$f"; then
    echo "[INFO] Patch $f"
    sed -i 's#/data_source#/datasource#g' "$f"
  fi
done

echo "[OK] Đã sửa toàn bộ link /data_source -> /datasource trong templates/."
