#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/RELEASE_VSP_FINAL_${TS}"
mkdir -p "$OUT"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need python3; need sha256sum; need tar; need node

log "== VSP FINAL RELEASE PACK P9 =="
log "[BASE]=$BASE [N]=$N [OUT]=$OUT"

log "== restart + smoke + stability =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_finalize_commercial_p6_v1.sh "$N" | tee "$OUT/finalize_p6_${TS}.log"

log "== resolve latest RID/RUN_DIR =="
J="$(curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS")"
RID="$(echo "$J" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid") or json.load(sys.stdin).get("ci_rid") or "")' 2>/dev/null || true)"
RUN_DIR="$(echo "$J" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("ci_run_dir") or "")' 2>/dev/null || true)"
[ -n "${RUN_DIR:-}" ] || { echo "[ERR] RUN_DIR empty from latest_rid_v1"; exit 2; }
log "[RUN_DIR]=$RUN_DIR"

log "== ensure ISO evidence exists (best-effort) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_iso_evidence_pack_p4_v1.sh | tee "$OUT/iso_p4_${TS}.log" || true

log "== pack report tgz (includes ISO if present) =="
/home/test/Data/SECURITY_BUNDLE/bin/pack_report.sh "$RUN_DIR" | tee "$OUT/pack_report_${TS}.log"
RPT_TGZ="$(ls -1t "$RUN_DIR"/*__REPORT.tgz 2>/dev/null | head -n1 || true)"
[ -n "${RPT_TGZ:-}" ] || { echo "[ERR] cannot find *__REPORT.tgz under RUN_DIR"; exit 2; }
cp -f "$RPT_TGZ" "$OUT/"
cp -f "$RUN_DIR/SHA256SUMS.txt" "$OUT/REPORT_SHA256SUMS.txt" 2>/dev/null || true

log "== pack audit bundle (auto COMMERCIAL snapshot) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v2.sh | tee "$OUT/audit_p2_${TS}.log"
AB="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.tgz 2>/dev/null | head -n1 || true)"
AS="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.SHA256SUMS.txt 2>/dev/null | head -n1 || true)"
[ -n "${AB:-}" ] || { echo "[ERR] cannot find AUDIT_BUNDLE_*.tgz"; exit 2; }
[ -n "${AS:-}" ] || { echo "[ERR] cannot find AUDIT_BUNDLE_*.SHA256SUMS.txt"; exit 2; }
cp -f "$AB" "$OUT/"
cp -f "$AS" "$OUT/"

log "== capture current UI meta =="
curl -sS "$BASE/api/vsp/dashboard_commercial_v2?ts=$TS" > "$OUT/dashboard_commercial_v2.json" || true
curl -sS "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=10" > "$OUT/runs_index.json" || true

log "== write README/STATUS =="
cat > "$OUT/README_RELEASE.txt" <<TXT
VSP Commercial Release — FINAL (UI 5 tabs + ISO evidence)
UI:
  $BASE/vsp4  (Ctrl+Shift+R)
Tabs:
  Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides
Artifacts:
  - *__REPORT.tgz  (report + findings + __meta/iso)
  - AUDIT_BUNDLE_*.tgz (includes COMMERCIAL snapshot)
Verify:
  sha256sum -c RELEASE_SHA256SUMS.txt
TXT

cat > "$OUT/STATUS_COMMERCIAL.txt" <<TXT
FINAL STATUS
- smoke 5 tabs: PASS
- stability: PASS (N=$N)
- console: expected CLEAN (no red)
- report tgz: present
- audit bundle: present
- ISO evidence: expected under report/__meta/iso (if iso pack ran)
RUN_DIR=$RUN_DIR
TXT

log "== build RELEASE_SHA256SUMS (no self-reference) + verify =="
(
  cd "$OUT"
  TMP="$(mktemp /tmp/release_sha_XXXXXX)"
  trap 'rm -f "$TMP" 2>/dev/null || true' EXIT
  find . -maxdepth 1 -type f ! -name 'RELEASE_SHA256SUMS.txt' -print0 \
    | sort -z \
    | xargs -0 sha256sum > "$TMP"
  mv -f "$TMP" RELEASE_SHA256SUMS.txt
  sha256sum -c RELEASE_SHA256SUMS.txt
)

log "[OK] FINAL RELEASE ready: $OUT"
ls -la "$OUT" | sed -n '1,200p'
