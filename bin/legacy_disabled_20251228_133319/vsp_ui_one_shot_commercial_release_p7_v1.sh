#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"   # stability rounds
TS="$(date +%Y%m%d_%H%M%S)"

OUTROOT="out_ci"
OUT="$OUTROOT/FINAL_RELEASE_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need python3; need tar; need sha256sum; need node

BUNDLE_JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js"

log "== VSP ONE-SHOT COMMERCIAL RELEASE P7 =="
log "[BASE]=$BASE [N]=$N [OUT]=$OUT"

# 0) restart clean
log "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh | tee "$OUT/restart_8910.log"

# 1) JS syntax check + auto-restore newest backup if fail
log "== node --check bundle =="
if ! node --check "$BUNDLE_JS" 2>&1 | tee "$OUT/node_check_1.log" ; then
  log "[WARN] node --check FAILED. Attempt auto-restore newest .bak_* then re-check..."
  cd "$(dirname "$BUNDLE_JS")"
  BAK="$(ls -1t vsp_bundle_commercial_v2.js.bak_* 2>/dev/null | head -n1 || true)"
  if [ -z "${BAK:-}" ]; then
    echo "[ERR] no backup found to restore under static/js/"; exit 9
  fi
  cp -f "vsp_bundle_commercial_v2.js" "$OUT/bundle_before_restore.js" || true
  cp -f "$BAK" "vsp_bundle_commercial_v2.js"
  log "[RESTORE] vsp_bundle_commercial_v2.js <= $BAK"
  cd /home/test/Data/SECURITY_BUNDLE/ui
  node --check "$BUNDLE_JS" 2>&1 | tee "$OUT/node_check_2.log"
fi

# 2) core endpoint health
log "== health endpoints =="
URLS=(
  "$BASE/vsp4"
  "$BASE/static/js/vsp_bundle_commercial_v2.js"
  "$BASE/api/vsp/latest_rid_v1"
  "$BASE/api/vsp/dashboard_commercial_v2"
  "$BASE/api/vsp/findings_latest_v1?limit=3"
  "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=3"
  "$BASE/api/vsp/rule_overrides_v1"
)
hf=0
for u in "${URLS[@]}"; do
  c="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$u" || echo 000)"
  printf "[HTTP] %s %s\n" "$c" "$u" | tee -a "$OUT/health.log"
  [ "$c" = "200" ] || hf=$((hf+1))
done
if [ "$hf" -ne 0 ]; then
  echo "[FAIL] health endpoints not all 200 (fails=$hf). See $OUT/health.log"; exit 10
fi

# 3) resolve RID + RUN_DIR
log "== resolve latest RID/RUN_DIR =="
J="$OUT/latest_rid.json"
curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS" > "$J"
RID="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("rid") or j.get("ci_rid") or "")' "$J" 2>/dev/null || true)"
RUN_DIR="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("ci_run_dir") or "")' "$J" 2>/dev/null || true)"
echo "[RID]=$RID" | tee "$OUT/rid.txt"
echo "[RUN_DIR]=$RUN_DIR" | tee "$OUT/run_dir.txt"
[ -n "${RID:-}" ] || { echo "[ERR] RID empty"; exit 11; }
[ -n "${RUN_DIR:-}" ] || { echo "[ERR] RUN_DIR empty"; exit 12; }

# 4) smoke 5 tabs (fast)
log "== smoke 5 tabs =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh | tee "$OUT/smoke_5tabs.log"

# 5) quick verify/export checks (best-effort, no fail if endpoint missing)
log "== verify/export (best-effort) =="
for ep in \
  "$BASE/api/vsp/verify_report_sha_v1?run_dir=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RUN_DIR")" \
  "$BASE/api/vsp/export_report_tgz_v1?run_dir=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RUN_DIR")" \
  "$BASE/api/vsp/open_report_html_v1?run_dir=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RUN_DIR")" \
; do
  c="$(curl -sS -m 6 -o /dev/null -w '%{http_code}' "$ep" || echo 000)"
  printf "[HTTP] %s %s\n" "$c" "$ep" | tee -a "$OUT/verify_export.log"
done

# 6) stability N rounds (no non-200)
log "== stability smoke (N=$N) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_smoke_p0_v1.sh "$N" | tee "$OUT/stability.log"

# 7) ISO evidence pack (writes ISO files + repack report tgz + repack audit bundle)
log "== ISO evidence pack P4 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_iso_evidence_pack_p4_v1.sh | tee "$OUT/iso_pack.log" || {
  echo "[FAIL] ISO pack failed. See $OUT/iso_pack.log"; exit 20; }

# 8) audit pack v2 (auto snapshot COMMERCIAL)
log "== audit pack P2 v2 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v2.sh | tee "$OUT/audit_pack.log"

# 9) create RELEASE folder (report tgz + sha + audit tgz + sha + latest COMMERCIAL snapshot + logs)
log "== build RELEASE folder =="
REL="$OUTROOT/RELEASE_${RID}_${TS}"
mkdir -p "$REL"

REPORT_TGZ="$RUN_DIR/${RID}__REPORT.tgz"
REPORT_SHA="$RUN_DIR/SHA256SUMS.txt"
[ -f "$REPORT_TGZ" ] || { echo "[ERR] missing report tgz: $REPORT_TGZ"; exit 30; }
[ -f "$REPORT_SHA" ] || { echo "[ERR] missing report sha: $REPORT_SHA"; exit 31; }

cp -f "$REPORT_TGZ" "$REL/"
cp -f "$REPORT_SHA" "$REL/REPORT_SHA256SUMS.txt"

AB="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.tgz 2>/dev/null | head -n1 || true)"
AS="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.SHA256SUMS.txt 2>/dev/null | head -n1 || true)"
[ -n "${AB:-}" ] && cp -f "$AB" "$REL/" || true
[ -n "${AS:-}" ] && cp -f "$AS" "$REL/" || true

COMM="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCIAL_* 2>/dev/null | head -n1 || true)"
if [ -n "${COMM:-}" ]; then
  mkdir -p "$REL/COMMERCIAL_SNAPSHOT"
  cp -a "$COMM/." "$REL/COMMERCIAL_SNAPSHOT/" || true
  echo "[OK] included COMMERCIAL snapshot: $COMM" | tee "$OUT/commercial_snapshot.txt"
else
  echo "[WARN] no COMMERCIAL_* found to include" | tee "$OUT/commercial_snapshot.txt"
fi

cp -a "$OUT/." "$REL/FINALIZE_LOGS/" 2>/dev/null || true

( cd "$REL" && sha256sum * 2>/dev/null || true ) > "$REL/RELEASE_SHA256SUMS.txt"

log "== DONE =="
log "[RELEASE]=$REL"
ls -la "$REL" | sed -n '1,120p'
log "[NEXT] Open UI: $BASE/vsp4 (Ctrl+Shift+R). Console must be clean."
