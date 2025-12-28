#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="$(mktemp -d /tmp/vsp_ui_xinxo_audit_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need sort; need uniq; need wc; need head; need python3; need date

ts(){ date +"%Y-%m-%d %H:%M:%S"; }
hr(){ printf '%*s\n' 110 | tr ' ' '-'; }

PAGES=(/vsp5 /runs /data_source /settings /rule_overrides)

# Notes patterns (commercial-grade):
# - TODO/FIXME: keep
# - DEBUG: only flag explicit debug banners/strings, not generic "debug" identifiers
# - N/A: literal N/A
NOTE_TODO_RE='TODO|FIXME'
NOTE_DEBUG_RE='SB DEBUG THEME ACTIVE|DEBUG TEMPLATE|Bản (DE\+"\+BUG|DEBUG)|\[VSP\]\[DEBUG\]'
NOTE_NA_RE='\bN/A\b'

echo "VSP UI XINXO AUDIT v1c  @ $(ts)"
echo "BASE=$BASE"
hr

echo "== [A] API quick =="
for ep in "/api/vsp/rid_latest" "/api/vsp/trend_v1" "/api/vsp/top_findings_v1?limit=5" "/api/vsp/release_latest"; do
  if curl -fsS "$BASE$ep" -o "$TMP/j.json" 2>/dev/null; then
    python3 - "$ep" "$TMP/j.json" <<'PY'
import json, sys
ep, path = sys.argv[1], sys.argv[2]
j=json.load(open(path,'r',encoding='utf-8'))
print("[OK]", ep, "keys=", ",".join(sorted(list(j.keys()))[:18]) + (" ..." if len(j.keys())>18 else ""))
PY
  else
    echo "[FAIL] $ep"
  fi
done
hr

echo "== [B] Per-tab scan + NOTES (strict) =="
printf "%-16s | %-6s | %-6s | %-6s | %-6s | %s\n" "TAB" "TODO" "DEBUG" "N/A" "TESTID" "MATCH"
hr

for P in "${PAGES[@]}"; do
  fn="$TMP/page_$(echo "$P" | tr '/' '_' ).html"
  if ! curl -fsS "$BASE$P" -o "$fn"; then
    printf "%-16s | %-6s | %-6s | %-6s | %-6s | %s\n" "$P" "FAIL" "FAIL" "FAIL" "FAIL" "fetch fail"
    continue
  fi

  js="$TMP/$(echo "$P" | tr '/' '_' )_js.txt"
  grep -oE '/static/js/[^"'\'' >]+' "$fn" | sed 's/[?].*$//' | sort -u > "$js" || true

  scan="$TMP/scan_$(echo "$P" | tr '/' '_' ).txt"
  : > "$scan"
  cat "$fn" > "$scan"
  while read -r a; do
    [[ -z "$a" ]] && continue
    curl -fsS "$BASE$a" 2>/dev/null | head -n 1200 >> "$scan" || true
  done < "$js"

  todo=0; dbg=0; na=0; tid=0; match=""
  if grep -qiE "$NOTE_TODO_RE" "$scan"; then todo=1; match="${match}TODO;"; fi
  if grep -qiE "$NOTE_DEBUG_RE" "$scan"; then dbg=1; match="${match}DEBUG;"; fi
  if grep -qiE "$NOTE_NA_RE" "$scan"; then na=1; match="${match}N/A;"; fi
  if grep -qiE "data-testid" "$scan"; then tid=1; fi

  printf "%-16s | %-6s | %-6s | %-6s | %-6s | %s\n" \
    "$P" "$todo" "$dbg" "$na" "$tid" "${match:-}"
done
hr
echo "[DONE]"
