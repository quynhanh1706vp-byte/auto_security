#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
OUT="$ROOT/out"
UI="$ROOT/ui"
STATIC_SUMMARY="$UI/static/summary_unified_latest.json"

echo "[i] ROOT  = $ROOT"
echo "[i] OUT   = $OUT"
echo "[i] DEST  = $STATIC_SUMMARY"

# Ưu tiên RUN dạng RUN_2* (RUN_2025...), sắp xếp theo mtime (mới nhất trước)
latest=""
candidates=$(ls -1dt "$OUT"/RUN_2* 2>/dev/null || true)

if [ -n "$candidates" ]; then
  latest=$(printf '%s\n' $candidates | head -n 1)
else
  # fallback: mọi RUN_* nếu không có RUN_2*
  latest=$(ls -1dt "$OUT"/RUN_* 2>/dev/null | head -n 1 || true)
fi

if [ -z "$latest" ]; then
  echo "[ERR] Không tìm thấy thư mục RUN_* trong $OUT"
  exit 1
fi

SRC="$latest/report/summary_unified.json"

echo "[i] Latest RUN (mtime) = $(basename "$latest")"
echo "[i] SRC summary        = $SRC"

if [ ! -f "$SRC" ]; then
  echo "[ERR] Không thấy $SRC"
  exit 1
fi

cp "$SRC" "$STATIC_SUMMARY"
echo "[DONE] Đã copy $SRC -> $STATIC_SUMMARY"
