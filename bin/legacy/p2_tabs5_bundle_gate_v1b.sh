#!/usr/bin/env bash
set -euo pipefail

# VSP_P2_TABS5_BUNDLE_GATE_V1B
# - Gate UI tabs5+bundle (OK)
# - Gate contract APIs with robust JSON fetch + debug on failure

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PAGES=(/vsp5 /runs /settings /data_source /rule_overrides)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need mktemp; need head; need wc; need date; need awk

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; exit 3; }

fetch_page(){
  local path="$1"
  local key
  key="$(echo "$path" | tr '/?' '__')"
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

fetch_json_strict(){
  # usage: fetch_json_strict "/api/..." out_body out_hdr
  local path="$1" out_body="$2" out_hdr="$3"
  local url="$BASE$path"
  local ts; ts="$(date +%s)"
  local code=""

  # retry a few times in case the UI just restarted
  for i in 1 2 3 4 5; do
    : > "$out_hdr"
    : > "$out_body"
    code="$(curl -sS -D "$out_hdr" -o "$out_body" -H 'Accept: application/json' \
      --connect-timeout 2 --max-time 8 \
      "${url}${url/*\?/?}&ts=${ts}.${i}" -w '%{http_code}' || true)"

    # treat 200 with non-empty body as success candidate
    if [[ "$code" == "200" && -s "$out_body" ]]; then
      return 0
    fi
    sleep 0.15
  done

  echo "[DEBUG] fetch failed: $path"
  echo "[DEBUG] last http_code=$code"
  echo "[DEBUG] headers:"
  sed -n '1,30p' "$out_hdr" | sed 's/\r$//'
  echo "[DEBUG] body preview (first 220 bytes):"
  head -c 220 "$out_body" || true
  echo
  return 1
}

echo "== [1] Pages tabs5 + bundle gate =="
for p in "${PAGES[@]}"; do
  check_page "$p"
done

echo "== [2] Contract API baseline (P0/P1) =="

RID_HDR="$TMP/rid_hdr.txt"
RID_BODY="$TMP/rid_body.txt"

fetch_json_strict "/api/vsp/rid_latest" "$RID_BODY" "$RID_HDR" || err "rid_latest unreachable or empty/non-json"

RID="$(python3 - <<'PY'
import json,sys
raw=open(sys.argv[1],'rb').read()
try:
    j=json.loads(raw.decode('utf-8','ignore').strip() or 'null')
except Exception as e:
    print("")
    raise
rid=(j or {}).get("rid","") if isinstance(j,dict) else ""
print(rid)
PY
"$RID_BODY")"

[[ -n "$RID" ]] || { echo "[DEBUG] rid_latest raw:"; cat "$RID_BODY" || true; err "rid_latest returned empty rid"; }
ok "rid_latest=$RID"

# run_gate_summary must have overall + counts_total
G_HDR="$TMP/g_hdr.txt"
G_BODY="$TMP/g_body.txt"
fetch_json_strict "/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" "$G_BODY" "$G_HDR" || err "run_gate_summary fetch failed"

python3 - <<'PY'
import json,sys
j=json.loads(open(sys.argv[1],'rb').read().decode('utf-8','ignore'))
assert j.get("ok") is True, "run_gate_summary ok!=true"
assert j.get("overall") not in (None,""), "missing overall"
ct=j.get("counts_total") or {}
assert isinstance(ct, dict) and len(ct)>0, "counts_total empty"
print("[OK] run_gate_summary overall=", j.get("overall"), "counts_total_keys=", len(ct))
PY "$G_BODY"

# findings_unified exists with limit
F_HDR="$TMP/f_hdr.txt"
F_BODY="$TMP/f_body.txt"
fetch_json_strict "/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=5" "$F_BODY" "$F_HDR" || err "findings_unified fetch failed"

python3 - <<'PY'
import json,sys
j=json.loads(open(sys.argv[1],'rb').read().decode('utf-8','ignore'))
arr=j.get("findings") or []
assert isinstance(arr, list), "findings not list"
print("[OK] findings_unified len(limit)=", len(arr))
PY "$F_BODY"

echo "== [PASS] VSP_P2_TABS5_BUNDLE_GATE_V1B =="
