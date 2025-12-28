#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="$(mktemp -d /tmp/vsp_locate_na_XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need sort; need head; need wc

PAGES=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== locate N/A in served HTML + JS =="
echo "BASE=$BASE"
echo

for P in "${PAGES[@]}"; do
  echo "---- PAGE $P ----"
  H="$TMP/page$(echo "$P" | tr '/' '_' ).html"
  curl -fsS "$BASE$P" -o "$H"

  echo "[HTML] N/A hits:"
  if grep -nE '\bN/A\b' "$H" | head -n 12; then :; else echo "  (none)"; fi

  # list JS assets
  JLIST="$TMP/js$(echo "$P" | tr '/' '_' ).txt"
  grep -oE '/static/js/[^"'\'' >]+' "$H" | sed 's/[?].*$//' | sort -u > "$JLIST" || true
  echo "[JS] assets count=$(wc -l < "$JLIST" | tr -d ' ')"

  # scan each JS for N/A (first few hits)
  while read -r a; do
    [ -z "${a:-}" ] && continue
    JS="$TMP/$(basename "$a")"
    curl -fsS "$BASE$a" -o "$JS" || continue
    if grep -nE '\bN/A\b' "$JS" >/dev/null 2>&1; then
      echo "  * HIT in $a"
      grep -nE '\bN/A\b' "$JS" | head -n 6 | sed 's/^/    /'
    fi
  done < "$JLIST"

  echo
done

echo "[DONE] (this script shows exact offending served lines)"
