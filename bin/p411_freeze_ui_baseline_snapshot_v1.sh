#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
OUT="$ROOT/out_ci/ui_baselines"
TS="$(date +%Y%m%d_%H%M%S)"
DEST="$OUT/UI_BASELINE_${TS}"
mkdir -p "$DEST"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sha256sum; need find; need cp; need mkdir

echo "== [P411] freeze UI baseline snapshot =="
cp -a "$ROOT/static/js" "$DEST/"
cp -a "$ROOT/templates" "$DEST/" 2>/dev/null || true

(
  cd "$DEST"
  find . -type f -print0 | xargs -0 sha256sum > SHA256SUMS.txt
)

echo "[OK] saved: $DEST"
echo "[OK] hashes: $DEST/SHA256SUMS.txt"
