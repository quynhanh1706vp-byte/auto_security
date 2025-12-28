#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/out_ui"
VERSION="VSP_UI_2025_V2.6"
TS="$(date +%Y%m%d_%H%M%S)"
PKG="$OUT_DIR/${VERSION}_$TS.zip"

mkdir -p "$OUT_DIR"

echo "[PACK] Root = $ROOT"
echo "[PACK] Creating $PKG"

cd "$ROOT"
zip -r "$PKG" \
  templates \
  static \
  vsp_demo_app.py \
  *.md \
  bin/vsp_* \
  bin/patch_* \
  requirements.txt 2>/dev/null || true

echo "[PACK] Done -> $PKG"
