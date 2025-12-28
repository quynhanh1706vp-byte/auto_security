#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci"
REL_DIR="/home/test/Data/SECURITY_BUNDLE/out_ci/releases"

LATEST_TGZ="$OUT/GOLDEN_UI_LATEST.tgz"
LATEST_SHA="$OUT/GOLDEN_UI_LATEST.tgz.sha256"

[ -L "$LATEST_TGZ" ] || { echo "[ERR] missing symlink: $LATEST_TGZ"; exit 2; }

# Resolve real tgz behind symlink
REAL_TGZ="$(readlink -f "$LATEST_TGZ")"
[ -f "$REAL_TGZ" ] || { echo "[ERR] resolved tgz not found: $REAL_TGZ"; exit 2; }

echo "[INFO] LATEST_TGZ=$LATEST_TGZ"
echo "[INFO] REAL_TGZ=$REAL_TGZ"

# Create/overwrite LATEST sha256 file (use name GOLDEN_UI_LATEST.tgz so sha256sum -c works)
HASH="$(sha256sum "$REAL_TGZ" | awk '{print $1}')"
echo "$HASH  GOLDEN_UI_LATEST.tgz" > "$LATEST_SHA"
echo "[OK] wrote $LATEST_SHA"

# Verify using the LATEST name (run inside OUT dir)
( cd "$OUT" && sha256sum -c "GOLDEN_UI_LATEST.tgz.sha256" )

# Release copy (both tgz + sha)
mkdir -p "$REL_DIR"
cp -f "$LATEST_TGZ" "$REL_DIR/VSP_UI_GOLDEN_LATEST.tgz"
cp -f "$LATEST_SHA" "$REL_DIR/VSP_UI_GOLDEN_LATEST.tgz.sha256"
echo "[OK] released: $REL_DIR/VSP_UI_GOLDEN_LATEST.tgz(+.sha256)"

# Verify release sha too
( cd "$REL_DIR" && sha256sum -c "VSP_UI_GOLDEN_LATEST.tgz.sha256" )

ls -lh "$OUT"/GOLDEN_UI_LATEST.tgz* "$REL_DIR"/VSP_UI_GOLDEN_LATEST.tgz*
