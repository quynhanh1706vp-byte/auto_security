#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p bin/legacy
moved=0
for f in bin/p[0-9]*.sh; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  dest="bin/legacy/$bn"
  [ ! -e "$dest" ] || dest="bin/legacy/${bn}.dup_${TS}"
  mv -f "$f" "$dest"
  chmod -x "$dest" || true
  echo "[OK] moved $f => $dest"
  moved=$((moved+1))
done
echo "[OK] moved_count=$moved"
