#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
D="out_ci"
[ -d "$D" ] || { echo "[SKIP] no $D"; exit 0; }

echo "[INFO] deleting ARCHIVE_BAKS_* older than 14 days in $D"
find "$D" -maxdepth 1 -type d -name 'ARCHIVE_BAKS_*' -mtime +14 -print -exec rm -rf {} \;
echo "[OK]"
