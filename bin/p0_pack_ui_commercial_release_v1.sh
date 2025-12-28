#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need tar; need date; need sha256sum; need find

TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="out_release"
mkdir -p "$OUTDIR"

PKG="$OUTDIR/UI_COMMERCIAL_${TS}.tgz"
MAN="$OUTDIR/UI_COMMERCIAL_${TS}.manifest.txt"
SUM="$OUTDIR/UI_COMMERCIAL_${TS}.sha256"

FILES=(
  "wsgi_vsp_ui_gateway.py"
  "vsp_demo_app.py"
  "templates"
  "static/css"
  "static/js/vsp_bundle_commercial_v2.js"
  "bin/p0_commercial_selfcheck_4tabs_v3c.sh"
)

echo "== pack ==" | tee "$MAN"
echo "[TS]=$TS" | tee -a "$MAN"
for f in "${FILES[@]}"; do
  if [ ! -e "$f" ]; then
    echo "[ERR] missing $f" | tee -a "$MAN"
    exit 2
  fi
  echo "[ADD] $f" | tee -a "$MAN"
done

tar -czf "$PKG" "${FILES[@]}"
sha256sum "$PKG" | tee "$SUM"

echo "[OK] pkg=$PKG"
echo "[OK] sha=$SUM"
echo "[OK] manifest=$MAN"
