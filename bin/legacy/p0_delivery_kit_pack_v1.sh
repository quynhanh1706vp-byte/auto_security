#!/usr/bin/env bash
set -euo pipefail

REL_DIR="/home/test/Data/SECURITY_BUNDLE/out_ci/releases"
UI_ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TS="$(date +%Y%m%d_%H%M%S)"

VER="${1:-VSP_UI_COMMERCIAL_20251225_01}"
COMM_TGZ="$REL_DIR/${VER}.tgz"
COMM_SHA="$REL_DIR/${VER}.tgz.sha256"

GOLD_TGZ="$REL_DIR/VSP_UI_GOLDEN_LATEST.tgz"
GOLD_SHA="$REL_DIR/VSP_UI_GOLDEN_LATEST.tgz.sha256"

RUNBOOK="$(ls -1t "$REL_DIR"/RUNBOOK_UI_COMMERCIAL_${VER}.md 2>/dev/null | head -n 1 || true)"
[ -n "$RUNBOOK" ] || RUNBOOK="$(ls -1t "$UI_ROOT"/out_ci/RUNBOOK_UI_COMMERCIAL.md 2>/dev/null | head -n 1 || true)"

DEPLOY="$UI_ROOT/bin/p0_deploy_from_release_safe_v2.sh"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need tar; need sha256sum; need mkdir; need cp

[ -f "$COMM_TGZ" ] || { echo "[ERR] missing: $COMM_TGZ"; exit 2; }
[ -f "$COMM_SHA" ] || { echo "[ERR] missing: $COMM_SHA"; exit 2; }
[ -f "$GOLD_TGZ" ] || { echo "[ERR] missing: $GOLD_TGZ"; exit 2; }
[ -f "$GOLD_SHA" ] || { echo "[ERR] missing: $GOLD_SHA"; exit 2; }
[ -f "$DEPLOY" ] || { echo "[ERR] missing: $DEPLOY"; exit 2; }
[ -n "${RUNBOOK:-}" ] || { echo "[ERR] missing runbook"; exit 2; }

OUT="$REL_DIR/DELIVERY_KIT_${VER}_${TS}"
PKG="$REL_DIR/DELIVERY_KIT_${VER}_${TS}.tgz"

mkdir -p "$OUT"
cp -f "$COMM_TGZ" "$OUT/"
cp -f "$COMM_SHA" "$OUT/"
cp -f "$GOLD_TGZ" "$OUT/"
cp -f "$GOLD_SHA" "$OUT/"
cp -f "$DEPLOY" "$OUT/"
cp -f "$RUNBOOK" "$OUT/"

tar -czf "$PKG" -C "$REL_DIR" "$(basename "$OUT")"
sha256sum "$(basename "$PKG")" > "${PKG}.sha256" 2>/dev/null || sha256sum "$PKG" > "${PKG}.sha256"

echo "[OK] KIT: $PKG"
echo "[OK] SHA: ${PKG}.sha256"
echo "[INFO] contents:"
tar -tzf "$PKG" | head -n 40
