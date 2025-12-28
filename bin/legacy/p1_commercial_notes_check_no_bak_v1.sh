#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need grep; need find; need head

echo "== scan WITHOUT backups (.bak_*, .broken_*, .disabled_*) =="
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) \
  ! -name '*.bak_*' ! -name '*.broken_*' ! -name '*.disabled_*' -print0 \
| xargs -0 grep -nH -E 'TODO|FIXME|DEBUG|\bN/A\b' 2>/dev/null \
| head -n 120 || echo "[OK] clean (no TODO/FIXME/DEBUG/N/A in active files)"
