#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/out_ci"
SRC="$BASE/uireq_v1"
DST="$BASE/ui_req_state"

mkdir -p "$SRC"

if [ -L "$DST" ]; then
  echo "[OK] ui_req_state already symlink -> $(readlink -f "$DST")"
  exit 0
fi

if [ -e "$DST" ] && [ ! -L "$DST" ]; then
  # nếu là directory thật: giữ lại nhưng sync file mới nhất từ uireq_v1 sang để compat
  echo "[WARN] $DST exists (not symlink). Will keep it and do a one-time sync."
  mkdir -p "$DST"
  rsync -a --ignore-existing "$SRC/" "$DST/" || true
  echo "[OK] one-time sync done (uireq_v1 -> ui_req_state)"
  exit 0
fi

ln -s "uireq_v1" "$DST"
echo "[OK] created symlink: $DST -> uireq_v1"
