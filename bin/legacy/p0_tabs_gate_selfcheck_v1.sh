#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need wc; need sed; need egrep

OK=0; WARN=0; ERR=0
ok(){ echo "[GREEN] $*"; OK=$((OK+1)); }
warn(){ echo "[AMBER] $*"; WARN=$((WARN+1)); }
err(){ echo "[RED] $*"; ERR=$((ERR+1)); }

check_tab(){
  local path="$1" min="$2"
  local tmp="/tmp/vsp_tab.$$"
  local head="/tmp/vsp_head.$$"
  curl -sS -I "$BASE$path" > "$head" || { err "$path HEAD fail"; return; }
  local code; code="$(egrep -i '^HTTP/' "$head" | head -n1 | awk '{print $2}')"
  [ "$code" = "200" ] || { err "$path code=$code"; rm -f "$head"; return; }

  curl -sS "$BASE$path" -o "$tmp" || { err "$path GET fail"; rm -f "$tmp" "$head"; return; }
  local bytes; bytes="$(wc -c < "$tmp" | tr -d ' ')"
  if [ "${bytes:-0}" -ge "$min" ]; then ok "$path bytes=$bytes"; else warn "$path bytes=$bytes (<$min)"; fi

  rm -f "$tmp" "$head"
}

check_api(){
  local path="$1"
  curl -fsS "$BASE$path" >/dev/null && ok "API $path" || err "API $path"
}

check_tab "/runs" 3000
check_tab "/data_source" 500
check_tab "/settings" 500
check_api "/api/vsp/runs?limit=1"
check_api "/api/vsp/release_latest"

echo
echo "[SUMMARY] GREEN=$OK AMBER=$WARN RED=$ERR"
[ "$ERR" -eq 0 ]
