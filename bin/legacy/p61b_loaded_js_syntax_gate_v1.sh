#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p61b_loaded_js_${TS}"; mkdir -p "$EVID"

echo "== [P61B] loaded-js syntax gate ==" | tee "$EVID/summary.txt"
echo "[INFO] BASE=$BASE" | tee -a "$EVID/summary.txt"

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid") or j.get("run_id") or "")' || true)"
echo "[INFO] RID=$RID" | tee -a "$EVID/summary.txt"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }

HTML="$EVID/vsp5.html"
curl -fsS "$BASE/vsp5?rid=$RID" -o "$HTML"

# extract loaded js urls
grep -oE '/static/js/[^"]+\.js[^"]*' "$HTML" \
  | sed 's/\?.*$//' \
  | sort -u > "$EVID/loaded_js_files.txt"

cnt="$(wc -l < "$EVID/loaded_js_files.txt" | tr -d ' ')"
echo "[INFO] loaded_js_files=$cnt" | tee -a "$EVID/summary.txt"

fails=0
: > "$EVID/js_syntax_fails.txt"
while IFS= read -r u; do
  f="${u#/}"
  if [ ! -f "$f" ]; then
    echo "[WARN] missing file on disk: $f" | tee -a "$EVID/summary.txt"
    continue
  fi
  if ! node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").check.err"; then
    echo "[FAIL] $f" | tee -a "$EVID/summary.txt"
    echo "$f" >> "$EVID/js_syntax_fails.txt"
    # print context
    bash bin/p61_js_error_context_v1.sh "$f" | tee -a "$EVID/summary.txt" || true
    fails=$((fails+1))
  fi
done < "$EVID/loaded_js_files.txt"

echo "[INFO] fails=$fails" | tee -a "$EVID/summary.txt"
if [ "$fails" -gt 0 ]; then
  echo "[FAIL] loaded-js syntax FAIL. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 1
fi
echo "[PASS] loaded-js syntax OK. Evidence=$EVID" | tee -a "$EVID/summary.txt"
