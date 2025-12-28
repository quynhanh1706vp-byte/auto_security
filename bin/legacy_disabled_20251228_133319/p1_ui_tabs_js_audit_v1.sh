#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
tmp="$(mktemp -d /tmp/vsp_tabs_js_audit_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [A] Extract JS from each tab =="
for t in "${tabs[@]}"; do
  echo "--- $t"
  curl -fsS "$BASE$t" -o "$tmp$(echo "$t" | tr '/' '_').html"
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp$(echo "$t" | tr '/' '_').html" \
    | sort -u | sed 's/^/  /' || true
done

echo
echo "== [B] Download those JS + grep for DS keywords =="
all_js="$tmp/all_js.txt"
: > "$all_js"
for f in "$tmp"/*.html; do
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$f" | sort -u >> "$all_js" || true
done
sort -u "$all_js" -o "$all_js"

while IFS= read -r js; do
  [ -n "$js" ] || continue
  out="$tmp/$(basename "${js%%\?*}")"
  curl -fsS "$BASE$js" -o "$out" || continue
done < "$all_js"

echo "[INFO] total js fetched: $(ls -1 "$tmp"/*.js 2>/dev/null | wc -l)"

echo
echo "== [C] Who references vsp_data_source_lazy_v1.js? =="
grep -RIn --line-number 'vsp_data_source_lazy_v1\.js' "$tmp"/*.js 2>/dev/null | head -n 30 || echo "  (none)"

echo
echo "== [D] Who references /data_source or run_file_allow? =="
grep -RIn --line-number '/data_source|/api/vsp/run_file_allow' "$tmp"/*.js 2>/dev/null | head -n 60 || echo "  (none)"

echo
echo "== [E] HTML status (200 expected) =="
for t in "${tabs[@]}"; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$t")"
  echo "$t => $code"
done
