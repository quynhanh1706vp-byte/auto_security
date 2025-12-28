#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need wc; need head; need date; need mktemp

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

pages=(/vsp5 /data_source /rule_overrides /settings)

echo "== [1] Pages HTML reachable + JS list =="
for P in "${pages[@]}"; do
  echo "-- $P --"
  H="$(curl -sS -o /tmp/vsp_page.$(echo $P|tr / _).html -w "%{http_code}" "$BASE$P" || echo 000)"
  if [ "$H" != "200" ]; then err "$P http=$H"; continue; fi
  ok "$P http=200"
  JS="$(grep -oE '/static/js/[^"]+' /tmp/vsp_page.$(echo $P|tr / _).html | sed 's/?v=.*$//' | sort -u)"
  echo "$JS" | sed 's/^/[JS] /'
done

echo
echo "== [2] Marker checks in key JS (safe, no pipefail SIGPIPE) =="

check_js_marker(){
  local file="$1" pat="$2"
  local tmp; tmp="$(mktemp -t vsp_jschk.XXXXXX)"
  # download fully to avoid SIGPIPE issues
  if ! curl -sS -o "$tmp" "$BASE/$file?cb=$(date +%s)"; then
    rm -f "$tmp"
    err "$file fetch failed"
    return 0
  fi
  if grep -qE "$pat" "$tmp"; then
    ok "$file has $pat"
  else
    err "$file missing $pat"
  fi
  rm -f "$tmp"
}

check_js_marker "static/js/vsp_tabs3_common_v3.js" "VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1"
check_js_marker "static/js/vsp_tabs3_common_v3.js" "VSP_DISABLE_OLD_FOLLOW_LATEST_POLL_V1"
check_js_marker "static/js/vsp_tabs3_common_v3.js" "VSP_NOISE_PANEL_ALLTABS_V1"

check_js_marker "static/js/vsp_dash_only_v1.js" "VSP_VSP5_RID_CHANGED_RELOAD_V1"
check_js_marker "static/js/vsp_p0_fetch_shim_v1.js" "VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1"

echo
echo "== [3] API runs latest + gate summary ok =="
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or "")')"
if [ -z "$RID" ]; then err "RID empty"; else ok "RID latest = $RID"; fi
if [ -n "$RID" ]; then
  curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=", j.get("ok"), "overall=", j.get("overall"));'
fi

echo
echo "== RESULT == OK=$OK WARN=$WARN ERR=$ERR"
[ "$ERR" -eq 0 ] || exit 1
