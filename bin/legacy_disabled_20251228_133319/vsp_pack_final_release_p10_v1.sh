#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need python3; need tar; need sha256sum; need node

BUNDLE_JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/vsp_bundle_commercial_v2.js"
[ -f "$BUNDLE_JS" ] || { echo "[ERR] missing $BUNDLE_JS"; exit 2; }

echo "== VSP FINAL PACK P10 =="
echo "[BASE]=$BASE [N]=$N [TS]=$TS"

# (1) hard reset + node check
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
node --check "$BUNDLE_JS"

# (2) resolve RID + RUN_DIR
J="$(curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS")"
RID="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("rid") or j.get("ci_rid") or "")' <<<"$J")"
RUN_DIR="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("ci_run_dir") or "")' <<<"$J")"
[ -n "${RID:-}" ] || { echo "[ERR] RID empty"; exit 3; }
[ -n "${RUN_DIR:-}" ] || { echo "[ERR] RUN_DIR empty"; exit 4; }
echo "[RID]=$RID"
echo "[RUN_DIR]=$RUN_DIR"

# (3) smoke + stability (P0)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_smoke_p0_v1.sh "$N" | tee "out_ci/stability_${RID}_${TS}.log"

# (4) ensure ISO evidence + rebuild report tgz (your P4 script already repacks audit too, safe)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_iso_evidence_pack_p4_v1.sh

# (5) create fresh audit bundle with COMMERCIAL snapshot
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v2.sh

# (6) locate artifacts
REPORT_TGZ="$(ls -1t "$RUN_DIR"/*__REPORT.tgz 2>/dev/null | head -n1 || true)"
REPORT_SHA="$(ls -1t "$RUN_DIR"/SHA256SUMS.txt 2>/dev/null | head -n1 || true)"
[ -f "$REPORT_TGZ" ] || { echo "[ERR] missing REPORT tgz under RUN_DIR"; exit 5; }
[ -f "$REPORT_SHA" ] || { echo "[ERR] missing SHA256SUMS.txt under RUN_DIR"; exit 6; }

AB="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.tgz | head -n1)"
AS="$(ls -1t /home/test/Data/SECURITY_BUNDLE/ui/out_ci/AUDIT_BUNDLE_*.SHA256SUMS.txt | head -n1)"
[ -f "$AB" ] || { echo "[ERR] missing audit bundle tgz"; exit 7; }
[ -f "$AS" ] || { echo "[ERR] missing audit bundle sha"; exit 8; }

# (7) release folder
REL="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/RELEASE_${RID}_${TS}"
mkdir -p "$REL"

cp -f "$REPORT_TGZ" "$REL/"
cp -f "$REPORT_SHA" "$REL/REPORT_SHA256SUMS.txt"
cp -f "out_ci/stability_${RID}_${TS}.log" "$REL/"
cp -f "$AB" "$REL/"
cp -f "$AS" "$REL/"

cat > "$REL/README_RELEASE.txt" <<TXT
VSP Commercial Release (UI 5 tabs + ISO evidence)
RID: $RID
RUN_DIR: $RUN_DIR

1) Verify integrity:
   sha256sum -c RELEASE_SHA256SUMS.txt

2) UI:
   $BASE/vsp4  (Ctrl+Shift+R)
   Tabs: Dashboard / Runs & Reports / Data Source / Settings / Rule Overrides

3) Report content check ISO:
   tar -tzf $(basename "$REPORT_TGZ") | grep -E 'report/__meta/iso/(ISO_EVIDENCE_INDEX\\.json|ISO_27001_MAP\\.csv)'

4) Audit bundle:
   tar -tzf $(basename "$AB") | head
TXT

cat > "$REL/STATUS_COMMERCIAL.txt" <<TXT
VSP COMMERCIAL RELEASE — FINAL STATUS
- UI smoke 5 tabs: PASS
- UI stability: PASS (N=$N)
- Report: present + ISO evidence included
- Audit bundle: present + COMMERCIAL snapshot included
TXT

# (8) rebuild RELEASE_SHA256SUMS safely (use your v2 fixer)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_release_fix_sha_p0_v2.sh "$REL"

# (9) pack final deliverable tarball
FINAL="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/VSP_FINAL_RELEASE_${RID}_${TS}.tgz"
( cd "$(dirname "$REL")" && tar -czf "$FINAL" "$(basename "$REL")" )

echo "[OK] FINAL=$FINAL"
sha256sum "$FINAL" | tee "${FINAL}.sha256"
echo "[OK] sha256=$(cat "${FINAL}.sha256")"
