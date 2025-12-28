#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need grep; need sed; need date; need sha256sum; need head; need sort; need uniq

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/smoke/SMOKE_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/smoke.log" >/dev/null; }
fail(){ echo "[FAIL] $*" | tee -a "$OUT/smoke.log" >/dev/null; exit 1; }
ok(){ echo "[OK] $*" | tee -a "$OUT/smoke.log" >/dev/null; }

fetch_head(){
  local url="$1" out="$2"
  curl -fsS -D "$out" -o /dev/null --connect-timeout 2 --max-time 6 "$url" || return 1
}
fetch_body(){
  local url="$1" out="$2"
  curl -fsS -o "$out" --connect-timeout 2 --max-time 8 --range 0-220000 "$url" || return 1
}

log "BASE=$BASE SVC=$SVC OUT=$OUT"

# 0) basic endpoints (5 tabs + /c/*)
pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  h="$OUT/HEAD$(echo "$p" | tr '/?' '__').txt"
  b="$OUT/BODY$(echo "$p" | tr '/?' '__').html"
  log "GET $p"
  fetch_head "$BASE$p" "$h" || fail "fetch head $p"
  code="$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$h")"
  [ "$code" = "200" ] || fail "$p HTTP=$code"
  fetch_body "$BASE$p" "$b" || fail "fetch body $p"
  sha256sum "$b" >> "$OUT/pages.sha256"
done
ok "5 tabs + /c/* all 200 + body saved"

# 1) verify P412 strip-at-source headers on /c/settings & /c/rule_overrides
for p in /c/settings /c/rule_overrides; do
  h="$OUT/HEAD$(echo "$p" | tr '/?' '__').txt"
  v="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-P412-STRIP:/{print $0}' "$h" | head -n1 || true)"
  echo "$v" | grep -qi 'X-VSP-P412-STRIP: 1' || fail "$p missing X-VSP-P412-STRIP: 1"
done
ok "P412 strip header present on /c/settings & /c/rule_overrides"

# 2) "P410 no-legacy 10x" style check: ensure HTML doesn't contain common legacy markers (best-effort)
# (không đụng console vì không chạy browser; chỉ soi HTML)
FORBID_RE='P405|legacy|installed[[:space:]]+P205|installed[[:space:]]+P306|installed[[:space:]]+P400|json[ _-]?collapse[ _-]?observer'
for i in $(seq 1 10); do
  b="$OUT/p410_vsp5_$i.html"
  fetch_body "$BASE/vsp5" "$b" || fail "p410 fetch /vsp5 #$i"
  if grep -Ein "$FORBID_RE" "$b" >/dev/null 2>&1; then
    grep -Ein "$FORBID_RE" "$b" | head -n 20 | tee -a "$OUT/p410_hits.txt" >/dev/null
    fail "p410: forbidden legacy marker found in /vsp5 HTML (see $OUT/p410_hits.txt)"
  fi
done
ok "P410 HTML 10x: no obvious legacy markers"

# 3) API probes (best-effort: hit what exists; fail if a probed endpoint returns non-200)
# (Nếu endpoint không tồn tại, sẽ không probe để tránh false-fail.)
probe_list=(
  "/api/vsp"
  "/api/vsp/top_findings_v2?limit=1"
  "/api/ui/runs_v3?limit=1&include_ci=1"
  "/api/vsp/run_status_v1"
)
for p in "${probe_list[@]}"; do
  # quick precheck existence: if 404, skip
  h="$OUT/API_HEAD$(echo "$p" | tr '/?&=' '____').txt"
  if fetch_head "$BASE$p" "$h"; then
    code="$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$h")"
    if [ "$code" = "404" ]; then
      log "SKIP API $p (404)"
      continue
    fi
    [ "$code" = "200" ] || fail "API $p HTTP=$code"
    ok "API $p => 200"
  else
    fail "API $p head fetch failed"
  fi
done

# 4) export endpoints discovery from /runs HTML (find href containing 'export' or 'pdf' or 'csv' or 'sarif')
runs_html="$OUT/BODY__runs.html"
grep -Eoi 'href="[^"]+"' "$runs_html" | sed 's/^href="//;s/"$//' \
  | grep -E '(export|csv|sarif|pdf|zip)' \
  | sed 's#^\(http[s]*://[^/]*\)##' \
  | grep -E '^/' \
  | sort -u > "$OUT/discovered_exports.txt" || true

if [ -s "$OUT/discovered_exports.txt" ]; then
  ok "Discovered export links: $(wc -l < "$OUT/discovered_exports.txt")"
  while IFS= read -r p; do
    h="$OUT/EXP_HEAD$(echo "$p" | tr '/?&=' '____').txt"
    fetch_head "$BASE$p" "$h" || fail "export head $p"
    code="$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$h")"
    [ "$code" = "200" ] || fail "export $p HTTP=$code"
    ok "export $p => 200"
  done < "$OUT/discovered_exports.txt"
else
  log "No export links discovered from /runs (OK if exports are not exposed there yet)"
fi

# summary
ok "SMOKE PASS. Artifacts in: $OUT"
echo "$OUT" > "$OUT/LATEST_PATH.txt"
