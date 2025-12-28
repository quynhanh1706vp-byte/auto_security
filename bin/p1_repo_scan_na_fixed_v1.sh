#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need grep; need find; need head

echo "== repo scan fixed-string 'N/A' (exclude backups) =="
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) \
  ! -name '*.bak_*' ! -name '*.broken_*' ! -name '*.disabled_*' -print0 \
| xargs -0 grep -nH -F "N/A" 2>/dev/null \
| head -n 120 || echo "[OK] no 'N/A' in active static/templates"
