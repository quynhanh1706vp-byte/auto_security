#!/usr/bin/env bash
set -euo pipefail

# IMPORTANT: Prefer BASE over VSP_UI_BASE so "BASE=... bash script" works.
BASE="${BASE:-${VSP_UI_BASE:-http://127.0.0.1:8910}}"
RID="${RID:-}"
TO="${TO:-$(command -v timeout || true)}"

tmp="$(mktemp -d /tmp/vsp_ui_audit_v2_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

ok(){ echo -e "[GREEN] $*"; }
warn(){ echo -e "[AMBER] $*"; }
fail(){ echo -e "[RED] $*"; }

G=0; A=0; R=0
pass(){ G=$((G+1)); ok "$*"; }
amber(){ A=$((A+1)); warn "$*"; }
red(){ R=$((R+1)); fail "$*"; }

need(){ command -v "$1" >/dev/null 2>&1 || { red "missing: $1"; exit 2; }; }
need curl; need python3; need awk; need grep; need sed; need head; need sort; need uniq; need wc; need tr

curl_do(){
  local maxs="${1:-6}"; shift || true
  if [ -n "$TO" ]; then
    "$TO" "${maxs}s" curl -fsS --connect-timeout 1 --max-time "$maxs" "$@"
  else
    curl -fsS --connect-timeout 1 --max-time "$maxs" "$@"
  fi
}

_choose_base(){
  # Prefer current BASE, then IPv4, then localhost, then IPv6.
  local cand=("$BASE" "http://127.0.0.1:8910" "http://localhost:8910" "http://[::1]:8910")
  for b in "${cand[@]}"; do
    [ -n "$b" ] || continue
    # Fast readiness probe first (usually <2s but allow headroom)
    if curl -fsS --connect-timeout 2 --max-time 10 -o /dev/null "$b/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
    # Fallback to /vsp5 which may be slow on warm-up
    if curl -fsS --connect-timeout 2 --max-time 15 -o /dev/null "$b/vsp5" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
  done
  return 1
}


wait_up(){
  _choose_base || { red "UI not reachable (all base candidates failed)"; return 1; }

  for i in $(seq 1 40); do
    # Prefer selfcheck (fast, stable)
    if curl_do 12 -o /dev/null "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      pass "UI up (selfcheck): $BASE"
      return 0
    fi
    # Accept /vsp5 too, but give it time
    if curl_do 18 -o /dev/null "$BASE/vsp5" >/dev/null 2>&1; then
      pass "UI up (/vsp5): $BASE"
      return 0
    fi
    sleep 0.25
  done

  red "UI not reachable: $BASE"
  return 1
}


hdr_count(){
  local p="$1" pat="$2"
  curl_do 4 -o /dev/null -D- "$BASE$p" | grep -Ei "$pat" | wc -l | tr -d ' '
}

check_tab(){
  local p="$1"
  local f="$tmp/tab_$(echo "$p" | tr '/?' '__').html"
  if curl_do 8 --range 0-240000 "$BASE$p" -o "$f" ; then
    pass "TAB $p => 200"
  else
    red "TAB $p => fetch failed"
    return 1
  fi

  local ct
  ct="$(curl_do 6 -o /dev/null -D- "$BASE$p" | awk 'BEGIN{IGNORECASE=1} /^Content-Type:/ {print $0; exit}')"
  if echo "$ct" | grep -qi 'text/html'; then
    pass "TAB $p => Content-Type html"
  else
    amber "TAB $p => Content-Type not html: ${ct:-N/A}"
  fi

  local csp rid
  csp="$(hdr_count "$p" '^Content-Security-Policy-Report-Only:')"
  rid="$(hdr_count "$p" '^X-VSP-AUTORID-INJECT:')"

  [ "$csp" -eq 1 ] && pass "TAB $p CSP_RO single" || amber "TAB $p CSP_RO count=$csp (expect 1)"

  if [ "$p" = "/vsp5" ]; then
    [ "$rid" -le 1 ] && pass "TAB /vsp5 AUTORID ok (count=$rid)" || amber "TAB /vsp5 AUTORID duplicated (count=$rid)"
  else
    [ "$rid" -eq 1 ] && pass "TAB $p AUTORID single" || amber "TAB $p AUTORID count=$rid (expect 1)"
  fi

  local jslist="$tmp/js_$(echo "$p" | tr '/?' '__').txt"
  grep -Eo 'src="[^"]+"' "$f" \
    | sed -E 's/^src="([^"]+)".*/\1/' \
    | grep -E '(\.js)(\?|$)' \
    | sed -E 's#^https?://[^/]+##' \
    | sort -u > "$jslist" || true

  local n
  n="$(wc -l < "$jslist" | tr -d ' ')"
  if [ "${n:-0}" -eq 0 ]; then
    amber "TAB $p: no JS detected (maybe inline)"
    return 0
  fi
  pass "TAB $p: js_count=$n"

  local bad=0
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if curl_do 8 -o /dev/null -D- "$BASE$u" | head -n 1 | grep -q "200" ; then
      :
    else
      bad=$((bad+1))
      echo "[BAD_JS] $p => $u" >> "$tmp/bad_js.log"
    fi
  done < "$jslist"
  [ "$bad" -eq 0 ] && pass "TAB $p: all JS 200" || amber "TAB $p: JS failures=$bad (see $tmp/bad_js.log)"
}

pick_latest_rid(){
  if [ -n "${RID:-}" ]; then pass "RID preset: $RID"; return 0; fi
  local j="$tmp/latest_rid.json"
  if ! curl_do 8 "$BASE/api/vsp/latest_rid_v1" -o "$j"; then
    amber "latest_rid_v1 failed; try runs"
    curl_do 8 "$BASE/api/vsp/runs?limit=5&offset=0" -o "$j" || return 1
  fi

  RID="$(python3 - <<PY
import json
try:
  obj=json.load(open("$j","r",encoding="utf-8"))
except Exception:
  print(""); raise SystemExit(0)

if isinstance(obj,dict):
  for k in ("rid","run_id","latest_rid","rid_latest","rid_latest_gate"):
    v=obj.get(k)
    if isinstance(v,str) and v.strip():
      print(v.strip()); raise SystemExit(0)
  runs=obj.get("runs") or obj.get("items") or obj.get("data")
  if isinstance(runs,list) and runs:
    for it in runs:
      if isinstance(it,dict):
        for k in ("rid","run_id","id"):
          v=it.get(k)
          if isinstance(v,str) and v.strip():
            print(v.strip()); raise SystemExit(0)
print("")
PY
)"
  [ -n "${RID:-}" ] && pass "Picked RID=$RID" || amber "Could not pick RID automatically"
}

check_api_json(){
  local name="$1" path="$2" maxs="${3:-8}"
  local out="$tmp/api_$(echo "$name" | tr ' /' '__').json"
  if ! curl_do "$maxs" "$BASE$path" -o "$out"; then
    amber "API $name FAIL: $path"
    return 1
  fi
  python3 - <<PY "$out" >/dev/null 2>&1 || { amber "API $name invalid-json: $path"; return 1; }
import json,sys
json.load(open(sys.argv[1],'r',encoding='utf-8'))
PY
  pass "API $name OK: $path"
}

check_export(){
  local fmt="$1"
  [ -n "${RID:-}" ] || { amber "EXPORT $fmt skipped (no RID)"; return 0; }

  local url1="$BASE/api/vsp/run_export_v3/$RID?fmt=$fmt"
  local url2="$BASE/api/vsp/run_export_v3?rid=$RID&fmt=$fmt"
  local f="$tmp/export_${fmt}.bin"

  if curl_do 12 --range 0-8000 "$url1" -o "$f" >/dev/null 2>&1; then
    :
  elif curl_do 12 --range 0-8000 "$url2" -o "$f" >/dev/null 2>&1; then
    :
  else
    amber "EXPORT fmt=$fmt FAIL"
    return 1
  fi

  if [ "$fmt" = "pdf" ]; then
    head -c 4 "$f" | grep -q '%PDF' && pass "EXPORT pdf OK" || amber "EXPORT pdf not PDF signature"
  elif [ "$fmt" = "zip" ]; then
    head -c 2 "$f" | grep -q 'PK' && pass "EXPORT zip OK" || amber "EXPORT zip not ZIP signature"
  else
    head -c 200 "$f" | tr -d '\0' | grep -qiE '<html|<!doctype' && pass "EXPORT html OK" || amber "EXPORT html not HTML signature"
  fi
}

echo "== [P28] commercial_ui_audit_v2 =="
wait_up
echo "BASE=$BASE"

echo "== [1] Tabs (HTML + headers + JS) =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  check_tab "$p" || true
done

echo "== [2] Pick RID =="
pick_latest_rid || true
echo "RID=${RID:-N/A}"

echo "== [3] Core APIs =="
check_api_json "selfcheck_p0" "/api/vsp/selfcheck_p0" 8 || true
check_api_json "runs" "/api/vsp/runs?limit=10&offset=0" 10 || true
check_api_json "runs_index_v3" "/api/vsp/runs_index_v3" 10 || true
check_api_json "datasource_v2" "/api/vsp/datasource_v2" 10 || true
check_api_json "findings" "/api/vsp/findings?limit=5" 10 || true
check_api_json "settings_v1" "/api/vsp/settings_v1" 10 || true
check_api_json "settings_ui_v1" "/api/vsp/settings_ui_v1" 10 || true
check_api_json "rule_overrides_v1" "/api/vsp/rule_overrides_v1" 10 || true
check_api_json "rule_overrides_ui_v1" "/api/vsp/rule_overrides_ui_v1" 10 || true
check_api_json "dashboard_v3" "/api/vsp/dashboard_v3" 12 || true
check_api_json "dashboard_commercial_v2" "/api/vsp/dashboard_commercial_v2" 12 || true
check_api_json "dashboard_extras_v1" "/api/vsp/dashboard_extras_v1" 25 || true

echo "== [4] Per-RID APIs (best-effort) =="
if [ -n "${RID:-}" ]; then
  check_api_json "findings_unified_v1" "/api/vsp/findings_unified_v1/$RID" 60 || true
  check_api_json "run_gate_summary_v1" "/api/vsp/run_gate_summary_v1/$RID" 12 || true
else
  amber "Per-RID checks skipped (no RID)"
fi

echo "== [5] Export (fmt=html/pdf/zip) =="
check_export html || true
check_export pdf  || true
check_export zip  || true

echo "== [SUMMARY] =="
echo "GREEN=$G AMBER=$A RED=$R"
[ "$R" -eq 0 ] && echo "[VERDICT] PASS (no RED)" || echo "[VERDICT] FAIL (has RED)"


# ===================== VSP_AUDIT_WAITUP_SLOW_V1 =====================
# Override base selection + wait_up to tolerate slow /vsp5 (>2s) and prefer fast selfcheck endpoint.

_choose_base(){
  local cand=("$BASE" "http://127.0.0.1:8910" "http://localhost:8910" "http://[::1]:8910")
  for b in "${cand[@]}"; do
    [ -n "$b" ] || continue
    # Prefer fast readiness probe first
    if curl -fsS --connect-timeout 2 --max-time 5 -o /dev/null "$b/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
    # Fallback to /vsp5 with bigger budget
    if curl -fsS --connect-timeout 2 --max-time 12 -o /dev/null "$b/vsp5" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
  done
  return 1
}

wait_up(){
  _choose_base || { red "UI not reachable (all base candidates failed)"; return 1; }
  for i in $(seq 1 40); do
    if curl_do 6 -o /dev/null "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      pass "UI up (selfcheck): $BASE"
      return 0
    fi
    if curl_do 12 -o /dev/null "$BASE/vsp5" >/dev/null 2>&1; then
      pass "UI up (/vsp5): $BASE"
      return 0
    fi
    sleep 0.25
  done
  red "UI not reachable: $BASE"
  return 1
}
# ===================== /VSP_AUDIT_WAITUP_SLOW_V1 =====================

