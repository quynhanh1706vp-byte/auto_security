#!/usr/bin/env bash
set -euo pipefail

# VSP_P2_TABS5_BUNDLE_GATE_V1
# Gate UI (tabs5) + bundle injected/present + no template tokens + core contracts OK.

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PAGES=(/vsp5 /runs /settings /data_source /rule_overrides)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need mktemp; need head; need wc; need date

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*"; exit 3; }

fetch_page(){
  local path="$1"
  local hdr="$TMP/hdr$(echo "$path" | tr '/?' '__').txt"
  local body="$TMP/body$(echo "$path" | tr '/?' '__').html"
  curl -fsS -D "$hdr" -o "$body" "$BASE$path"
  echo "$hdr|$body"
}

get_hdr(){
  local hdr="$1" key="$2"
  # prints first match value (case-insensitive)
  awk -v k="$key" 'BEGIN{IGNORECASE=1} $0 ~ "^"k":" {sub(/^[^:]+:[[:space:]]*/,""); gsub(/\r/,""); print; exit}' "$hdr"
}

extract_v(){
  # extract v digits from script src occurrences
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
  if [[ -z "$xb" ]]; then
    err "$path missing header X-VSP-P2-BUNDLE (expected injected/present)"
  fi
  if [[ "$xb" != "injected" && "$xb" != "present" && "$xb" != "err" ]]; then
    err "$path X-VSP-P2-BUNDLE unexpected: $xb"
  fi
  [[ "$xb" == "err" ]] && err "$path bundle hook returned err"

  # must contain autorid + bundle
  grep -q "vsp_tabs4_autorid_v1.js" "$body" || err "$path missing vsp_tabs4_autorid_v1.js"
  grep -q "vsp_bundle_tabs5_v1.js" "$body" || err "$path missing vsp_bundle_tabs5_v1.js"

  # no template token dirt
  if grep -q "{{" "$body"; then err "$path contains '{{' token dirt"; fi
  if grep -q "}}" "$body"; then err "$path contains '}}' token dirt"; fi

  # v digits consistency: if autorid has v digits, bundle should reuse same digits
  local v_aut v_bun
  v_aut="$(extract_v "$body" 'vsp_tabs4_autorid_v1\.js\?v=[0-9]{6,}' || true)"
  v_bun="$(extract_v "$body" 'vsp_bundle_tabs5_v1\.js\?v=[0-9]{6,}' || true)"
  if [[ -n "$v_aut" && -n "$v_bun" && "$v_aut" != "$v_bun" ]]; then
    err "$path v mismatch: autorid(v=$v_aut) vs bundle(v=$v_bun)"
  fi

  ok "$path tabs5+bundle OK (X-VSP-P2-BUNDLE=$xb v_aut=${v_aut:-na} v_bun=${v_bun:-na})"
}

echo "== [1] Pages tabs5 + bundle gate =="
for p in "${PAGES[@]}"; do
  check_page "$p"
done

echo "== [2] Contract API baseline (P0/P1) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
rid=j.get("rid") or ""
print(rid)
PY
)"
[[ -n "$RID" ]] || err "rid_latest empty"
ok "rid_latest=$RID"

# run_gate_summary must have overall + counts_total
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
assert j.get("ok") is True, "run_gate_summary ok!=true"
assert j.get("overall") not in (None,""), "missing overall"
ct=j.get("counts_total") or {}
assert isinstance(ct, dict) and len(ct)>0, "counts_total empty"
print("[OK] run_gate_summary overall=", j.get("overall"), "counts_total_keys=", len(ct))
PY

# findings_unified exists with limit
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=5" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
arr=j.get("findings") or []
assert isinstance(arr, list), "findings not list"
print("[OK] findings_unified len(limit)=", len(arr))
PY

echo "== [PASS] VSP_P2_TABS5_BUNDLE_GATE_V1 =="
