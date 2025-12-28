#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

f="${1:-}"
[ -n "$f" ] || { echo "Usage: $0 static/js/xxx.js"; exit 2; }
[ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }

echo "== node --check $f =="
out="$(node --check "$f" 2>&1 || true)"
echo "$out"

ln="$(echo "$out" | sed -n 's/.*:\([0-9]\+\).*/\1/p' | head -n 1 || true)"
if [ -n "${ln:-}" ]; then
  a=$(( ln-12 )); [ "$a" -lt 1 ] && a=1
  b=$(( ln+12 ))
  echo "== context lines $a..$b =="
  nl -ba "$f" | sed -n "${a},${b}p"
fi
