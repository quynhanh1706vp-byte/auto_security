#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_3c_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need grep; need sed; need awk; need sort; need uniq

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p52_3c_${TS}"
mkdir -p "$ATT"

latest_gate="$(ls -1dt "$OUT"/p51_1_gate_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_gate:-}" ] && [ -d "$latest_gate" ] || { echo "[ERR] no p51_1_gate found"; exit 2; }

H="$latest_gate/html_marker_hits.txt"
if [ ! -f "$H" ]; then
  echo "[ERR] missing $H"; exit 2
fi

cp -f "$H" "$EVID/" || true

# Extract unique marker lines (keep small)
grep -Ein 'DEBUG|TODO|TRACE|not available|N/A|undefined|null' "$H" \
  | head -n 200 > "$EVID/marker_lines_top200.txt" || true

# Search in repo
: > "$EVID/grep_hits.txt"
for kw in DEBUG TODO TRACE "not available" "N/A" undefined null; do
  echo "===== KW: $kw =====" >> "$EVID/grep_hits.txt"
  grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' \
    -e "$kw" templates static/js 2>/dev/null | head -n 80 >> "$EVID/grep_hits.txt" || true
done

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P52.3c report attached: $ATT"
