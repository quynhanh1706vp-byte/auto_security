#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p520_${TS}"
mkdir -p "$OUT"
log(){ echo "$*" | tee -a "$OUT/run.log"; }

log "== [P520] BASE=$BASE TS=$TS =="

log "== [1] top_findings_v2 cache (P504) =="
for i in 1 2 3; do
  curl -sS -D "$OUT/topfind_$i.hdr" -o /dev/null -w "time_total=%{time_total}\n" \
    "$BASE/api/vsp/top_findings_v2?limit=5" > "$OUT/topfind_$i.time" || true
  hit="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-P504-FCACHE:/{print $2}' "$OUT/topfind_$i.hdr" | tr -d '\r' | head -n1)"
  t="$(cat "$OUT/topfind_$i.time" | tr -d '\r' | tail -n1)"
  log "call#$i fcache=${hit:-?} ${t:-}"
done
grep -qi "X-VSP-P504-FCACHE: HIT" "$OUT/topfind_2.hdr" && log "[OK] P504 HIT confirmed" || log "[WARN] P504 HIT not confirmed"

log "== [2] CSP headers single-line + COOP/CORP =="
curl -sS -D "$OUT/csp.hdr" -o /dev/null "$BASE/c/dashboard" || true
csp_count="$(awk 'BEGIN{IGNORECASE=1} /^Content-Security-Policy:/{c++} END{print c+0}' "$OUT/csp.hdr")"
coop="$(awk 'BEGIN{IGNORECASE=1} /^Cross-Origin-Opener-Policy:/{print $2}' "$OUT/csp.hdr" | tr -d '\r' | head -n1)"
corp="$(awk 'BEGIN{IGNORECASE=1} /^Cross-Origin-Resource-Policy:/{print $2}' "$OUT/csp.hdr" | tr -d '\r' | head -n1)"
log "csp_count=$csp_count coop=${coop:-} corp=${corp:-}"
if [ "$csp_count" -eq 1 ]; then log "[OK] CSP single header"; else log "[FAIL] CSP duplicated or missing"; fi
[ "${coop:-}" = "same-origin" ] && log "[OK] COOP same-origin" || log "[WARN] COOP missing/other"
[ "${corp:-}" = "same-origin" ] && log "[OK] CORP same-origin" || log "[WARN] CORP missing/other"

log "== [3] CSP report sink persist (P519) =="
RID="p520_${TS}"
resp_hdr="$OUT/csp_post.hdr"
curl -sS -D "$resp_hdr" -o /dev/null -X POST -H 'Content-Type: application/json' \
  --data "{\"csp-report\":{\"document-uri\":\"$RID\",\"blocked-uri\":\"x\",\"violated-directive\":\"script-src\"}}" \
  "$BASE/api/ui/csp_report_v1" || true
p519="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-P519-CSP-LOG:/{print $2}' "$resp_hdr" | tr -d '\r' | head -n1)"
log "p519_hdr=${p519:-}"
if [ "${p519:-}" = "1" ]; then log "[OK] P519 header present"; else log "[FAIL] P519 header missing"; fi
LOGF="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/csp_reports.log"
if [ -f "$LOGF" ] && tail -n 200 "$LOGF" | grep -q "$RID"; then
  log "[OK] csp_reports.log contains RID=$RID"
else
  log "[FAIL] csp_reports.log missing RID=$RID"
fi

log "== [4] runs_v3 filter marker (optional, P500B) =="
curl -sS -D "$OUT/runsv3.hdr" -o /dev/null "$BASE/api/vsp/runs_v3?limit=1&include_ci=1" || true
f="$(awk 'BEGIN{IGNORECASE=1} /^X-VSP-P500B-RUNS3-FILTER:/{print $2}' "$OUT/runsv3.hdr" | tr -d '\r' | head -n1)"
log "runs_filter_hdr=${f:-none}"

log "[DONE] OUT=$OUT"
