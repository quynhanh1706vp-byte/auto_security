#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need wc; need head; need python3; need date

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

pages=(/vsp5 /runs /settings /data_source /rule_overrides)

echo "== [1] 5 tabs: HTTP 200 + text/html =="
for P in "${pages[@]}"; do
  code="$(curl -sS -o /tmp/vsp_page.$$ -w "%{http_code}" "$BASE$P" || true)"
  ct="$(curl -sS -I "$BASE$P" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}' | head -n1)"
  if [ "$code" = "200" ] && echo "$ct" | grep -qi "text/html"; then
    ok "$P code=200 ct=$ct"
  else
    err "$P code=$code ct=$ct"
  fi
done

echo
echo "== [2] JS src in each page: must have v=<digits> and must NOT contain {{ asset_v }} =="
for P in "${pages[@]}"; do
  echo "-- $P --"
  H="$(curl -sS "$BASE$P" || true)"
  echo "$H" | grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' || true
  if echo "$H" | grep -q "{{"; then
    err "$P: template tokens found"
  else
    ok "$P: no template tokens"
  fi
  if echo "$H" | grep -qE '\.js\?v=[0-9]+'; then
    ok "$P: has numeric v="
  else
    err "$P: missing numeric v="
  fi
done

echo
echo "== [3] /vsp5 must include tabs+topbar scripts =="
H5="$(curl -sS "$BASE/vsp5" || true)"
echo "$H5" | grep -q "vsp_tabs4_autorid_v1.js" && ok "/vsp5 has tabs js" || err "/vsp5 missing tabs js"
echo "$H5" | grep -q "vsp_topbar_commercial_v1.js" && ok "/vsp5 has topbar js" || err "/vsp5 missing topbar js"

echo
echo "== [4] run_file_allow contract: HTTP 200 + JSON parseable + ok boolean =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
if [ -z "$RID" ]; then
  err "rid_latest empty"
else
  ok "rid_latest=$RID"
  J="$(curl -sS -w "\nHTTP=%{http_code}\n" "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" || true)"
  http="$(echo "$J" | tail -n1 | sed 's/HTTP=//')"
  body="$(echo "$J" | sed '$d')"
  if [ "$http" = "200" ]; then
    ok "run_file_allow http=200"
    python3 - <<PY >/tmp/vsp_rfa_check.$$ 2>/tmp/vsp_rfa_err.$$
import json,sys
j=json.loads(sys.stdin.read() or "{}")
assert isinstance(j.get("ok"), bool)
print("keys=", sorted(list(j.keys()))[:15])
PY
    if [ $? -eq 0 ]; then ok "run_file_allow JSON parse OK"; else err "run_file_allow JSON parse FAIL: $(head -n1 /tmp/vsp_rfa_err.$$)"; fi
  else
    err "run_file_allow http=$http"
  fi
fi

echo
echo "== SUMMARY =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
[ "$ERR" -eq 0 ]
