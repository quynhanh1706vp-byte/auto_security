#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
SNAPDIR="out_ci/snapshots"
mkdir -p "$SNAPDIR"

OUT_TMP="$SNAPDIR/ui_safe_${TS}.tgz"
OUT_LATEST="$SNAPDIR/ui_safe_latest.tgz"

echo "== freeze SAFE snapshot =="
# tập trung vào template + static assets
tar -czf "$OUT_TMP" \
  templates/vsp_dashboard_2025.html \
  static/js static/css static/img static/vendor 2>/dev/null

cp -f "$OUT_TMP" "$OUT_LATEST"

# checksum
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT_LATEST" > "$OUT_LATEST.sha256"
fi

echo "[OK] SAFE latest => $OUT_LATEST"
ls -lh "$OUT_LATEST" "$OUT_LATEST.sha256" 2>/dev/null || true
