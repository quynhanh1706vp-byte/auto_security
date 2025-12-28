#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need ss; need egrep; need date

GREEN(){ echo -e "\033[32m$*\033[0m"; }
AMBER(){ echo -e "\033[33m$*\033[0m"; }
RED(){ echo -e "\033[31m$*\033[0m"; }

OK=0; WARN=0; FAIL=0

say(){
  echo "== $* =="
}

pass(){ OK=$((OK+1)); GREEN "[PASS] $*"; }
warn(){ WARN=$((WARN+1)); AMBER "[WARN] $*"; }
fail(){ FAIL=$((FAIL+1)); RED "[FAIL] $*"; }

say "VSP UI commercial self-check (P0/P1) @ $(date +%F\ %T)"
echo "[BASE] $BASE"
echo

say "1) Port listening"
if ss -ltnp | egrep -q '127\.0\.0\.1:8910'; then
  pass "8910 listening"
else
  fail "8910 NOT listening"
fi

say "2) / redirects to /vsp5 (200 or 302 acceptable)"
code_root="$(curl -sS -o /dev/null -w "%{http_code}" -I "$BASE/" || echo 000)"
if [[ "$code_root" =~ ^(200|302)$ ]]; then
  pass "/ => $code_root"
else
  fail "/ => $code_root"
fi

say "3) /vsp5 returns 200"
code_vsp5="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/vsp5" || echo 000)"
if [ "$code_vsp5" = "200" ]; then
  pass "/vsp5 => 200"
else
  fail "/vsp5 => $code_vsp5"
fi

say "4) /api/vsp/runs contract smoke + 80/80 stability"
j1="$(curl -sS "$BASE/api/vsp/runs?limit=20" || true)"
if echo "$j1" | jq -e '.ok==true and (.items|type=="array")' >/dev/null 2>&1; then
  pass "runs?limit=20 JSON ok/items"
else
  fail "runs?limit=20 JSON invalid"
fi

# Contract fields (P1) - warning if missing (not always mandatory depending stage)
if echo "$j1" | jq -e '(.rid_latest|type=="string") and (.cache_ttl|type=="number") and (.roots_used|type=="array") and (.scan_cap_hit|type=="boolean")' >/dev/null 2>&1; then
  pass "runs contract fields present (rid_latest/cache_ttl/roots_used/scan_cap_hit)"
else
  warn "runs contract fields missing/incomplete (P1 contract not fully applied?)"
fi

# 80/80
bad=0
for i in $(seq 1 80); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/runs?limit=20" || echo 000)"
  if [ "$code" != "200" ]; then
    bad=1
    fail "runs stability failed at i=$i code=$code"
    break
  fi
done
if [ "$bad" = "0" ]; then
  pass "runs stability 80/80 => 200"
fi

say "5) Export endpoints smoke (optional)"
# We only WARN if missing because some environments don't have report files for latest RID
rid="$(echo "$j1" | jq -r '.items[0].run_id // .items[0].rid // empty' 2>/dev/null || true)"
if [ -n "$rid" ]; then
  pass "rid_latest candidate: $rid"
  # best-effort HEAD checks
  for ep in \
    "$BASE/api/vsp/export_csv?rid=$rid" \
    "$BASE/api/vsp/export_tgz?rid=$rid&scope=reports" \
    "$BASE/api/vsp/sha256?rid=$rid&name=reports/run_gate_summary.json"
  do
    c="$(curl -sS -o /dev/null -w "%{http_code}" -I "$ep" || echo 000)"
    if [[ "$c" =~ ^(200|302|404)$ ]]; then
      # 404 is acceptable if artifact not present yet
      if [ "$c" = "404" ]; then warn "export (missing artifact) $c $ep"; else pass "export $c $ep"; fi
    else
      warn "export unexpected $c $ep"
    fi
  done
else
  warn "no rid found from runs list; skip export smoke"
fi

echo
say "RESULT"
echo "OK=$OK WARN=$WARN FAIL=$FAIL"

if [ "$FAIL" -gt 0 ]; then
  RED "OVERALL=RED"
  exit 3
fi
if [ "$WARN" -gt 0 ]; then
  AMBER "OVERALL=AMBER"
  exit 0
fi
GREEN "OVERALL=GREEN"
exit 0
