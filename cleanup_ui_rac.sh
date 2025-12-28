#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TRASH_PATCH="$ROOT/_trash_patches"
TRASH_MISC="$ROOT/_trash_misc"

echo "[i] ROOT        = $ROOT"
echo "[i] TRASH_PATCH = $TRASH_PATCH"
echo "[i] TRASH_MISC  = $TRASH_MISC"

mkdir -p "$TRASH_PATCH" "$TRASH_MISC"

echo "[i] === Gom script patch_*.sh vào _trash_patches/ (không xóa) ==="
PATCH_FILES=$(ls patch_*.sh 2>/dev/null || true)
if [ -n "$PATCH_FILES" ]; then
  echo "[i] Sẽ move các file:"
  echo "$PATCH_FILES"
  mv patch_*.sh "$TRASH_PATCH"/
  echo "[OK] Đã move patch_*.sh vào $TRASH_PATCH"
else
  echo "[INFO] Không có patch_*.sh trong $ROOT"
fi

echo "[i] === Gom file backup tạm (*.bak *~ *.swp) vào _trash_misc/ (không xóa) ==="
MISC_FILES=$(ls *.bak *~ *.swp 2>/dev/null || true)
if [ -n "$MISC_FILES" ]; then
  echo "[i] Sẽ move các file:"
  echo "$MISC_FILES"
  mv *.bak *~ *.swp "$TRASH_MISC"/ 2>/dev/null || true
  echo "[OK] Đã move file backup tạm vào $TRASH_MISC"
else
  echo "[INFO] Không có file backup tạm trong $ROOT"
fi

echo "[DONE] Chỉ move rác, KHÔNG đụng vào bản chuẩn (app.py, templates, static, bin...)."
