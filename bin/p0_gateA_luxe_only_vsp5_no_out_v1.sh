#!/usr/bin/env bash
set -u
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="/tmp/vsp_gateA_no_out_$$"
mkdir -p "$OUT"
TO="$(command -v timeout || true)"

pages=(/vsp5 /runs /data_source /settings /rule_overrides)

fetch(){
  local p="$1"
  local f="$OUT/$(echo "$p" | tr '/?' '__').html"
  if [ -n "$TO" ]; then
    $TO 5s curl -fsS --connect-timeout 1 --max-time 4 --range 0-120000 "$BASE$p" -o "$f" \
      || { echo "[FAIL] fetch $p"; return 1; }
  else
    curl -fsS --connect-timeout 1 --max-time 4 --range 0-120000 "$BASE$p" -o "$f" \
      || { echo "[FAIL] fetch $p"; return 1; }
  fi
  echo "[OK] fetch $p bytes=$(wc -c <"$f")"
  return 0
}

echo "== Gate A: LUXE must appear ONLY in /vsp5 =="
fail=0

for p in "${pages[@]}"; do
  fetch "$p" || { fail=$((fail+1)); continue; }
done

echo
for p in "${pages[@]}"; do
  f="$OUT/$(echo "$p" | tr '/?' '__').html"
  [ -s "$f" ] || continue

  hit="$(grep -n "vsp_dashboard_luxe_v1\.js" "$f" | head -n 1 || true)"
  if [ "$p" = "/vsp5" ]; then
    if [ -n "$hit" ]; then
      echo "[PASS] $p has luxe: $hit"
    else
      echo "[FAIL] $p missing luxe"
      fail=$((fail+1))
    fi
  else
    if [ -n "$hit" ]; then
      echo "[FAIL] $p MUST NOT have luxe: $hit"
      fail=$((fail+1))
    else
      echo "[PASS] $p no luxe"
    fi
  fi
done

echo
echo "[DONE] fail=$fail out=$OUT"
exit "$fail"
