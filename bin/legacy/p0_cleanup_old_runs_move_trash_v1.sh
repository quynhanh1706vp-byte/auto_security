#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/home/test/Data/SECURITY_BUNDLE/out}"
TRASH="${TRASH:-/home/test/Data/SECURITY_BUNDLE/out_trash}"
KEEP="${KEEP:-50}"           # giữ lại N run mới nhất
DO_MOVE="${DO_MOVE:-0}"      # 0=dry-run, 1=move to trash

mkdir -p "$TRASH"

echo "== ROOT=$ROOT KEEP=$KEEP DO_MOVE=$DO_MOVE TRASH=$TRASH =="

mapfile -t dirs < <(find "$ROOT" -maxdepth 1 -type d -name 'RUN_*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{print $2}')
total="${#dirs[@]}"
echo "found RUN_* = $total"

if [ "$total" -le "$KEEP" ]; then
  echo "[OK] nothing to clean"
  exit 0
fi

echo "== candidates to move (older) =="
idx=0
for d in "${dirs[@]}"; do
  idx=$((idx+1))
  if [ "$idx" -le "$KEEP" ]; then
    continue
  fi
  echo "$d"
done

if [ "$DO_MOVE" != "1" ]; then
  echo "[DRY-RUN] set DO_MOVE=1 to move old runs into trash"
  exit 0
fi

echo "== moving to trash =="
idx=0
for d in "${dirs[@]}"; do
  idx=$((idx+1))
  if [ "$idx" -le "$KEEP" ]; then
    continue
  fi
  base="$(basename "$d")"
  mv -f "$d" "$TRASH/${base}" && echo "[MOVED] $base"
done
echo "[DONE]"
