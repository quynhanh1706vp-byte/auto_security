#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci/p523_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

fail(){ echo "[FAIL] $*" | tee -a "$OUT/gate.log"; exit 1; }
ok(){ echo "[OK] $*" | tee -a "$OUT/gate.log"; }

pages=(/vsp5 /runs /data_source /settings /rule_overrides)

# IMPORTANT: quote items containing ? and &
apis=(
  "/api/healthz"
  "/api/readyz"
  "/api/vsp/top_findings_v2?limit=5"
  "/api/ui/runs_v3?limit=10&include_ci=1"
)

ok "BASE=$BASE"
ok "OUT=$OUT"

# 1) HTML pages must return 200 and not be empty/blank
for p in "${pages[@]}"; do
  f="$OUT/$(echo "$p" | tr '/?' '__').html"
  code="$(curl -sS -o "$f" -w "%{http_code}" "$BASE$p" || true)"
  [ "$code" = "200" ] || fail "$p http=$code"
  sz="$(wc -c < "$f" | tr -d ' ')"
  [ "$sz" -ge 800 ] || fail "$p too small (${sz} bytes)"
  grep -qiE "<html|<!doctype" "$f" || fail "$p no html doctype"
  ok "$p 200 size=$sz"
done

# 2) APIs must return 200 (readyz can be 503 only if readiness broken)
for a in "${apis[@]}"; do
  hdr="$OUT/api_$(echo "$a" | tr '/?&=' '____').hdr"
  body="$OUT/api_$(echo "$a" | tr '/?&=' '____').json"
  code="$(curl -sS -D "$hdr" -o "$body" -w "%{http_code}" "$BASE$a" || true)"
  if [[ "$a" == "/api/readyz" ]]; then
    [ "$code" = "200" ] || fail "readyz not ready (http=$code). Fix readiness first."
  else
    [ "$code" = "200" ] || fail "$a http=$code"
  fi
  ok "$a http=$code"
done

# 3) CSP header sanity
hdr="$OUT/vsp5_headers.txt"
curl -sS -D "$hdr" -o /dev/null "$BASE/vsp5"
grep -qi '^Content-Security-Policy:' "$hdr" || fail "missing CSP header on /vsp5"
ok "CSP header present"

ok "P523 PASS => UI commercial gate OK"
echo "EVIDENCE: $OUT"
