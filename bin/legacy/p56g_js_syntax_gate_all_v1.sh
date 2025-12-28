#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56g_js_syntax_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need find; need sort; need wc; need tee

echo "== [P56G] JS syntax gate (all static/js/*.js) ==" | tee "$EVID/summary.txt"
fails=0

mapfile -t files < <(find static/js -maxdepth 1 -type f -name "*.js" | sort)
echo "files_count=${#files[@]}" | tee -a "$EVID/summary.txt"

for f in "${files[@]}"; do
  if node --check "$f" >"$EVID/$(basename "$f").ok.txt" 2>"$EVID/$(basename "$f").err.txt"; then
    echo "[OK] $f" | tee -a "$EVID/summary.txt" >/dev/null
    rm -f "$EVID/$(basename "$f").err.txt"
  else
    echo "[FAIL] $f" | tee -a "$EVID/summary.txt"
    fails=$((fails+1))
  fi
done

echo "fails=$fails" | tee -a "$EVID/summary.txt"
echo "[DONE] Evidence: $EVID"
[ "$fails" -eq 0 ] || exit 2
