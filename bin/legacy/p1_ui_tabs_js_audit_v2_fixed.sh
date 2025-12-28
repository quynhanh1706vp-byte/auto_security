#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

tmp="$(mktemp -d /tmp/vsp_tabs_js_audit_v2_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/html" "$tmp/js"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [A] Fetch HTML + extract JS per tab =="
all_js="$tmp/all_js.txt"
: > "$all_js"

for t in "${tabs[@]}"; do
  safe="$(echo "$t" | sed 's#[/ ]#_#g')"
  html="$tmp/html/${safe}.html"
  echo "--- $t"
  curl -fsS "$BASE$t" -o "$html"
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$html" | sort -u | tee "$tmp/html/${safe}.jslist" \
    | sed 's/^/  /' || true
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$html" | sort -u >> "$all_js" || true
done

sort -u "$all_js" -o "$all_js"
echo
echo "[INFO] total unique js urls: $(wc -l < "$all_js" | tr -d ' ')"

echo
echo "== [B] Download JS =="
cnt=0
while IFS= read -r js; do
  [ -n "$js" ] || continue
  # strip query for filename
  name="$(basename "${js%%\?*}")"
  out="$tmp/js/$name"
  curl -fsS "$BASE$js" -o "$out"
  cnt=$((cnt+1))
done < "$all_js"
echo "[INFO] total js fetched: $cnt"
ls -1 "$tmp/js" | head -n 30 | sed 's/^/  /'

echo
echo "== [C] Quick grep: who references DS lazy module? =="
grep -RIn --line-number 'vsp_data_source_lazy_v1\.js' "$tmp/js"/*.js 2>/dev/null | head -n 40 || echo "  (none)"

echo
echo "== [D] Quick grep: who hits run_file_allow / findings_unified? =="
grep -RIn --line-number '/api/vsp/run_file_allow|findings_unified\.json|findings_unified\.csv|run_gate_summary\.json' \
  "$tmp/js"/*.js 2>/dev/null | head -n 80 || echo "  (none)"

echo
echo "== [E] Duplicate JS content check (sha256) =="
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp/js" && sha256sum *.js | sort) > "$tmp/sha.txt"
  awk '{print $1}' "$tmp/sha.txt" | sort | uniq -c | sort -nr | head -n 20
else
  echo "  (sha256sum missing)"
fi

echo
echo "== [F] Status codes =="
for t in "${tabs[@]}"; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$t")"
  echo "$t => $code"
done

echo
echo "[OK] audit done. tmp=$tmp"
