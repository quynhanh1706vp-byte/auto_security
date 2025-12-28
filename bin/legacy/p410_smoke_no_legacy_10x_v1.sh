#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need awk; need head

pages=(/c/settings /c/rule_overrides)

# các “dấu vết legacy” đã từng gây duplicate
forbidden=(
  "Gate summary (live)"
  "PIN default (stored local)"
  "Paste overrides JSON here"
  "Prefer backend"
  "fallback localStorage"
  "VSP_RULE_OVERRIDES_EDITOR_P0_V1"
  "Rule Overrides (live from"
)

fetch(){
  local p="$1"
  curl -fsS --connect-timeout 2 --max-time 6 --range 0-220000 "$BASE$p"
}

echo "== [P410] smoke no-legacy markers (10x) =="
for p in "${pages[@]}"; do
  echo "---- $p ----"
  for i in $(seq 1 10); do
    html="$(fetch "$p" || true)"
    if [ -z "${html:-}" ]; then
      echo "[FAIL] $p call#$i: empty/failed fetch"; exit 3
    fi
    bad=0
    for k in "${forbidden[@]}"; do
      if echo "$html" | grep -Fq "$k"; then
        echo "[FAIL] $p call#$i: found legacy marker: $k"
        bad=1
      fi
    done
    if [ "$bad" -ne 0 ]; then
      echo "---- snippet ----"
      echo "$html" | head -n 80
      exit 4
    fi
    echo "[OK] $p call#$i"
  done
done

echo ""
echo "[GREEN] PASS: no legacy markers detected across 10 reloads per tab."
