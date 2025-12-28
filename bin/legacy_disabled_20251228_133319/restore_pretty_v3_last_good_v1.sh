#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_pretty_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_broken_current_${TS}"
echo "[BACKUP] $F.bak_broken_current_${TS}"

# Candidates: backups newest first
mapfile -t CANDS < <(ls -1t "${F}.bak_"* 2>/dev/null || true)

if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "[ERR] no backups found like ${F}.bak_*"
  exit 2
fi

echo "[INFO] trying backups (newest first) until node --check passes..."
GOOD=""

for c in "${CANDS[@]}"; do
  if node --check "$c" >/dev/null 2>&1; then
    GOOD="$c"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] no backup parses OK with node --check"
  echo "[HINT] list backups: ls -1t ${F}.bak_* | head"
  exit 3
fi

cp -f "$GOOD" "$F"
echo "[OK] restored $F from $GOOD"
node --check "$F"
echo "[OK] node --check passed on restored $F"
