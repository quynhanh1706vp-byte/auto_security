#!/usr/bin/env bash
set -euo pipefail

BASE="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
cd "$BASE"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need sort; need tail; need tar; need sha256sum; need mkdir; need rm

DROP="$(ls -1 VSP_COMMERCIAL_DROP_*.tgz 2>/dev/null | sort | tail -n 1)"
[ -n "${DROP:-}" ] || { echo "[ERR] no commercial drop tgz found in $BASE"; exit 2; }

RUNBOOK="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/INSTALL_RUNBOOK.md"
[ -f "$RUNBOOK" ] || { echo "[ERR] missing $RUNBOOK"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="VSP_COMMERCIAL_DROP_${TS}.tgz"

tmp="/tmp/vsp_drop_repack_${TS}"
rm -rf "$tmp"
mkdir -p "$tmp"
tar -xzf "$DROP" -C "$tmp"

cp -f "$RUNBOOK" "$tmp/INSTALL_RUNBOOK.md"

tar -czf "$OUT" -C "$tmp" .
sha256sum "$OUT" | tee "$OUT.sha256"

echo "[DONE] NEW_DROP=$BASE/$OUT"
