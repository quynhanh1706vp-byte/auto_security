#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/RELEASE_VSP_FINAL_STRICT_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/pack.log" ; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need python3; need tar; need sha256sum; need node; need ss; need ps

BUNDLE_JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js"
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing bundle: $BUNDLE_JS"; exit 2; }

log "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh | tee "$OUT/restart.log"

log "== node --check bundle =="
node --check "$BUNDLE_JS" | tee "$OUT/nodecheck.log"

log "== smoke 5 tabs =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh | tee "$OUT/smoke_5tabs.log"

log "== resolve latest RID/RUN_DIR =="
curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS" > "$OUT/latest_rid.json"
RID="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("rid") or j.get("ci_rid") or "")' "$OUT/latest_rid.json")"
RUN_DIR="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("ci_run_dir") or "")' "$OUT/latest_rid.json")"
[ -n "${RID:-}" ] || { echo "[ERR] RID empty"; exit 3; }
[ -n "${RUN_DIR:-}" ] || { echo "[ERR] RUN_DIR empty"; exit 3; }
log "[RID]=$RID"
log "[RUN_DIR]=$RUN_DIR"

log "== capture UI meta =="
curl -sS "$BASE/api/vsp/dashboard_commercial_v2" > "$OUT/dashboard_commercial_v2.json" || true
curl -sS "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=3" > "$OUT/runs_index.json" || true

log "== stability STRICT (N=$N) =="
# STRICT: nếu fail 1 phát -> dump diag -> exit
FAIL=0
for i in $(seq 1 "$N"); do
  for u in \
    "$BASE/vsp4" \
    "$BASE/api/vsp/latest_rid_v1" \
    "$BASE/api/vsp/dashboard_commercial_v2" \
    "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1" \
    "$BASE/static/js/vsp_bundle_commercial_v2.js"
  do
    code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "$u" || echo 000000)"
    if [ "$code" != "200" ]; then
      echo "[FAIL] i=$i code=$code url=$u" | tee -a "$OUT/stability_strict.log"
      FAIL=1
      break
    fi
  done
  [ "$FAIL" -eq 0 ] || break
done

if [ "$FAIL" -ne 0 ]; then
  log "== DIAG (STRICT FAIL) =="
  ss -lntp | grep ':8910' | tee "$OUT/diag_ss_8910.txt" || true
  ps -ef | grep -E 'gunicorn .*8910' | grep -v grep | tee "$OUT/diag_ps_gunicorn.txt" || true
  tail -n 200 out_ci/ui_8910.error.log > "$OUT/diag_ui_8910_error_tail.log" || true
  dmesg -T | egrep -i 'killed process|out of memory|oom' | tail -n 80 > "$OUT/diag_dmesg_oom_tail.log" || true
  echo "[ERR] stability STRICT failed. Check $OUT/*diag* and out_ci/ui_8910.error.log" >&2
  exit 10
fi
echo "== RESULT == [OK] stable (STRICT)" | tee -a "$OUT/stability_strict.log"

log "== ensure ISO evidence + rebuild report tgz =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_iso_evidence_pack_p4_v1.sh | tee "$OUT/iso_p4.log"

log "== pack audit bundle (auto COMMERCIAL snapshot) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v2.sh | tee "$OUT/audit_p2.log"

log "== collect artifacts into release dir =="
# report tgz + sha
cp -f "$RUN_DIR/${RID}__REPORT.tgz" "$OUT/" 2>/dev/null || cp -f "$RUN_DIR/"*__REPORT.tgz "$OUT/" || true
cp -f "$RUN_DIR/SHA256SUMS.txt" "$OUT/REPORT_SHA256SUMS.txt" 2>/dev/null || true

# latest audit bundle from ui/out_ci
AB="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.tgz | head -n1)"
AS="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.SHA256SUMS.txt | head -n1)"
cp -f "$AB" "$OUT/"
cp -f "$AS" "$OUT/"

cat > "$OUT/STATUS_COMMERCIAL.txt" <<TXT
VSP COMMERCIAL RELEASE — FINAL (STRICT)

UI:
- URL: $BASE/vsp4
- Tabs: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
- Smoke 5 tabs: PASS
- Stability STRICT: PASS ($N rounds)

Report:
- REPORT.tgz includes ISO evidence under report/__meta/iso/
Audit:
- AUDIT_BUNDLE includes COMMERCIAL snapshot
TXT

log "== build RELEASE_SHA256SUMS (no self-reference) + verify =="
TMP="$(mktemp /tmp/release_sha_XXXXXX)"
trap 'rm -f "$TMP" 2>/dev/null || true' EXIT
find "$OUT" -maxdepth 1 -type f ! -name 'RELEASE_SHA256SUMS.txt' -print0 \
  | sort -z \
  | xargs -0 sha256sum > "$TMP"
cp -f "$TMP" "$OUT/RELEASE_SHA256SUMS.txt"
( cd "$OUT" && sha256sum -c RELEASE_SHA256SUMS.txt )

log "[OK] FINAL RELEASE ready: $OUT"
ls -la "$OUT" | tail -n +1
