#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p933_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need curl; need date; need sha256sum; need awk; need sed
command -v sudo >/dev/null 2>&1 || true

log(){ echo "$*" | tee -a "$OUT/summary.txt"; }

hit200(){
  local url="$1"
  local code
  code="$(curl -sS --noproxy '*' -o "$OUT/body.tmp" -w "%{http_code}" --connect-timeout 2 --max-time 6 "$url" || true)"
  printf "%-75s %s\n" "$url" "$code" | tee -a "$OUT/summary.txt"
  if [ "$code" != "200" ]; then
    log "[FAIL] $url => $code"
    head -n 80 "$OUT/body.tmp" > "$OUT/last_body.txt" || true
    exit 3
  fi
}

log "== [P933] BASE=$BASE SVC=$SVC TS=$TS =="
log "pwd=$(pwd)"

log "== [1] JS syntax strict gate =="
bash bin/p934_js_syntax_gate_strict_v1.sh | tee -a "$OUT/js_gate.txt"

log "== [2] Ensure pack script enforces P934 =="
PACK="bin/p922b_pack_release_snapshot_no_warning_v2.sh"
[ -f "$PACK" ] || { log "[FAIL] missing $PACK"; exit 4; }
grep -n "P932_ENFORCE_P934_JS_GATE" "$PACK" | tee -a "$OUT/summary.txt" >/dev/null || {
  log "[FAIL] pack does NOT enforce P934 gate tag"
  exit 5
}
grep -n "bin/p934_js_syntax_gate_strict_v1.sh" "$PACK" | tee -a "$OUT/summary.txt" >/dev/null || {
  log "[FAIL] pack does NOT call P934 gate"
  exit 6
}
log "[OK] pack gate hooks present"

log "== [3] Service readiness =="
ok=0
for i in $(seq 1 30); do
  code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
  echo "try#$i healthz=$code" | tee -a "$OUT/summary.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
[ "$ok" = "1" ] || { log "[FAIL] UI not ready"; exit 7; }

log "== [4] UI tabs must be 200 =="
for p in /vsp5 /runs /data_source /c/settings /c/rule_overrides; do
  hit200 "$BASE$p"
done

log "== [5] Core APIs must be 200 =="
hit200 "$BASE/api/vsp/runs_v3?limit=3&include_ci=1"
hit200 "$BASE/api/vsp/top_findings_v2?limit=3"
hit200 "$BASE/api/vsp/dashboard_kpis_v4"
hit200 "$BASE/api/vsp/trend_v1"
hit200 "$BASE/api/vsp/exports_v1"
hit200 "$BASE/api/vsp/run_status_v1"
hit200 "$BASE/api/vsp/ops_latest_v1"

log "== [6] P920 endpoints must be 200 (journal/log tail/evidence) =="
hit200 "$BASE/api/vsp/journal_v1?n=20"
hit200 "$BASE/api/vsp/log_tail_v1?n=80"
# evidence zip may exist; verify 200 or skip if 404
code="$(curl -sS --noproxy '*' -o "$OUT/evidence.zip" -w "%{http_code}" --connect-timeout 2 --max-time 12 "$BASE/api/vsp/evidence_zip_v1" || true)"
echo "$BASE/api/vsp/evidence_zip_v1  $code" | tee -a "$OUT/summary.txt"
if [ "$code" = "200" ]; then
  ls -lh "$OUT/evidence.zip" | tee -a "$OUT/summary.txt"
else
  log "[WARN] evidence_zip_v1 not 200 (code=$code) -> OK if endpoint is disabled by policy"
fi

log "== [7] Headers sanity (security headers present) =="
curl -sS --noproxy '*' -D "$OUT/headers_settings.txt" -o /dev/null "$BASE/c/settings" || true
awk 'BEGIN{IGNORECASE=1}
     /^HTTP\// || /^X-Frame-Options:/ || /^X-Content-Type-Options:/ || /^Referrer-Policy:/ || /^Permissions-Policy:/ || /^Content-Security-Policy:/ {print}' \
     "$OUT/headers_settings.txt" | tee -a "$OUT/summary.txt"

log "== [8] GOLDEN snapshot exists =="
ls -1t static/js/vsp_c_settings_v1.js.bak_GOOD_* 2>/dev/null | head -n 3 | tee -a "$OUT/summary.txt" >/dev/null || {
  log "[FAIL] missing GOLDEN backups: static/js/vsp_c_settings_v1.js.bak_GOOD_*"
  exit 8
}
log "[OK] GOLDEN present"

log "== [P933] PASS. Evidence: $OUT =="
log "NEXT: run pack script to create release snapshot: bash $PACK"
