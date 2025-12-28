#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
DST="out_ci/ARCHIVE_BAKS_${TS}"
mkdir -p "$DST/static_js" "$DST/templates"

echo "[DST]=$DST"

# move backups
find static/js -maxdepth 1 -type f -name "*.bak_*" -print -exec mv -f {} "$DST/static_js/" \;
find templates -maxdepth 1 -type f -name "*.bak_*" -print -exec mv -f {} "$DST/templates/" \;

echo "[OK] moved .bak_* into $DST"
