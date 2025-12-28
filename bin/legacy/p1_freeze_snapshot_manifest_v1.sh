#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need find; need sha256sum; need sort; need mkdir

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/SNAPSHOT_${TS}"
mkdir -p "$OUT"

# capture key files (wsgi + templates + static assets)
find . -type f \
  \( -name 'wsgi_vsp_ui_gateway.py' -o -path './templates/*.html' -o -path './static/js/*.js' -o -path './static/css/*.css' \) \
  ! -path './.venv/*' ! -path './node_modules/*' ! -path './out_ci/*' \
  -print0 \
| xargs -0 sha256sum \
| sort -k2 > "$OUT/manifest.sha256"

echo "[OK] wrote $OUT/manifest.sha256"
