#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="$(mktemp -d /tmp/vsp_trace_na_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need sort; need head; need wc

PAGES=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== TRACE N/A (fixed string) in audit scan =="
echo "BASE=$BASE"
echo

for P in "${PAGES[@]}"; do
  echo "---- TAB $P ----"
  H="$TMP/page$(echo "$P" | tr '/' '_' ).html"
  curl -fsS "$BASE$P" -o "$H"

  JLIST="$TMP/js$(echo "$P" | tr '/' '_' ).txt"
  grep -oE '/static/js/[^"'\'' >]+' "$H" | sed 's/[?].*$//' | sort -u > "$JLIST" || true

  SCAN="$TMP/scan$(echo "$P" | tr '/' '_' ).txt"
  : > "$SCAN"
  cat "$H" >> "$SCAN"
  while read -r a; do
    [ -z "${a:-}" ] && continue
    curl -fsS "$BASE$a" 2>/dev/null | head -n 2000 >> "$SCAN" || true
  done < "$JLIST"

  echo "[SCAN] N/A hits:"
  if grep -nF "N/A" "$SCAN" | head -n 20; then :; else echo "  (none)"; fi
  echo
done

echo "[DONE]"
