#!/usr/bin/env bash
set -euo pipefail

# VSP_P2_TABS5_BUNDLE_GATE_V1D
# Fix JSON parsing: use python3 -c (script in argv), JSON via stdin.

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PAGES=(/vsp5 /runs /settings /data_source /rule_overrides)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need mktemp; need head; need wc; need date; need awk

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*"; exit 3; }

fetch_page(){
  local path="$1"
  local key; key="$(echo "$path" | tr '/?' '__')"
  local hdr="$TMP/hdr${key}.txt"
  local body="$TMP/body${key}.html"
  curl -fsS -D "$hdr" -o "$body" "$BASE$path"
  echo "$hdr|$body"
}

get_hdr(){
  local hdr="$1" key="$2"
  awk -v k="$key" 'BEGIN{IGNORECASE=1} $0 ~ "^"k":" {sub(/^[^:]+:[[:space:]]*/,""); gsub(/\r/,""); print; exit}' "$hdr"
}

extract_v(){
  local body="$1" re="$2"
  grep -oE "$re" "$body" | head -n 1 | sed -E 's/.*v=([0-9]{6,}).*/\1/'
}

check_page(){
  local path="$1"
  local out; out="$(fetch_page "$path")"
  local hdr="${out%%|*}" body="${out#*|}"

  local status; status="$(head -n 1 "$hdr" | tr -d '\r')"
  echo "-- $path --"
  echo "$status"
  echo "[INFO] size=$(wc -c <"$body")"

  echo "$status" | grep -qE ' 200 ' || err "$path not 200"

  local ct; ct="$(get_hdr "$hdr" "Content-Type" || true)"
  echo "$ct" | grep -qi 'text/html' || err "$path Content-Type not html: $ct"

  local xb; xb="$(get_hdr "$hdr" "X-VSP-P2-BUNDLE" || true)"
  [[ -n "$xb" ]] || err "$path missing header X-VSP-P2-BUNDLE"
  [[ "$xb" != "err" ]] || err "$path bundle hook returned err"

  grep -q "vsp_tabs4_autorid_v1.js" "$body" || err "$path missing vsp_tabs4_autorid_v1.js"
  grep -q "vsp_bundle_tabs5_v1.js" "$body" || err "$path missing vsp_bundle_tabs5_v1.js"

  grep -q "{{" "$body" && err "$path contains '{{' token dirt" || true
  grep -q "}}" "$body" && err "$path contains '}}' token dirt" || true

  local v_aut v_bun
  v_aut="$(extract_v "$body" 'vsp_tabs4_autorid_v1\.js\?v=[0-9]{6,}' || true)"
  v_bun="$(extract_v "$body" 'vsp_bundle_tabs5_v1\.js\?v=[0-9]{6,}' || true)"
  if [[ -n "$v_aut" && -n "$v_bun" && "$v_aut" != "$v_bun" ]]; then
    err "$path v mismatch: autorid(v=$v_aut) vs bundle(v=$v_bun)"
  fi

  ok "$path tabs5+bundle OK (X-VSP-P2-BUNDLE=$xb v_aut=${v_aut:-na} v_bun=${v_bun:-na})"
}

add_ts(){
  local url="$1"
  local ts; ts="$(date +%s)"
  if [[ "$url" == *"?"* ]]; then echo "${url}&ts=${ts}"; else echo "${url}?ts=${ts}"; fi
}

curl_json_retry(){
  local url="$1"
  local i body
  for i in 1 2 3 4 5; do
    body="$(curl -sS -H 'Accept: application/json' --connect-timeout 2 --max-time 8 "$(add_ts "$url")" || true)"
    if [[ -n "${body//[[:space:]]/}" ]]; then
      echo "$body"
      return 0
    fi
    sleep 0.15
  done

  echo "[DEBUG] curl_json_retry failed: $url" >&2
  echo "[DEBUG] HEADERS (first 20 lines):" >&2
  curl -sS -I --connect-timeout 2 --max-time 8 "$url" | sed -n '1,20p' >&2 || true
  echo "[DEBUG] BODY preview (first 220 bytes):" >&2
  curl -sS --connect-timeout 2 --max-time 8 "$url" | head -c 220 >&2 || true
  echo >&2
  return 1
}

echo "== [1] Pages tabs5 + bundle gate =="
for p in "${PAGES[@]}"; do
  check_page "$p"
done

echo "== [2] Contract API baseline (P0/P1) =="

RID_JSON="$(curl_json_retry "$BASE/api/vsp/rid_latest")" || err "rid_latest unreachable/empty"
RID="$(printf '%s' "$RID_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid","") if isinstance(j,dict) else "")')"
[[ -n "$RID" ]] || { echo "[DEBUG] rid_latest raw: $RID_JSON"; err "rid_latest returned empty rid"; }
ok "rid_latest=$RID"

G_JSON="$(curl_json_retry "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json")" || err "run_gate_summary fetch failed"
printf '%s' "$G_JSON" | python3 -c '
import sys,json
j=json.load(sys.stdin)
assert j.get("ok") is True
assert j.get("overall") not in (None,"")
ct=j.get("counts_total") or {}
assert isinstance(ct, dict) and len(ct)>0
print("[OK] run_gate_summary overall=", j.get("overall"), "counts_total_keys=", len(ct))
'

F_JSON="$(curl_json_retry "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=5")" || err "findings_unified fetch failed"
printf '%s' "$F_JSON" | python3 -c '
import sys,json
j=json.load(sys.stdin)
arr=j.get("findings") or []
assert isinstance(arr, list)
print("[OK] findings_unified len(limit)=", len(arr))
'

echo "== [PASS] VSP_P2_TABS5_BUNDLE_GATE_V1D =="
