#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need bash; need curl; need jq; need date

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] BASE=$BASE"

echo
echo "== (1) restart clean =="
rm -f /tmp/vsp_ui_8910.lock || true
if [ -x bin/p0_ui_8910_restart_clean_v1.sh ]; then
  bin/p0_ui_8910_restart_clean_v1.sh >/dev/null || true
else
  echo "[WARN] missing bin/p0_ui_8910_restart_clean_v1.sh (skipping)"
fi

# Ensure API is reachable
curl -sS -I "$BASE/" | sed -n '1,8p' >/dev/null

echo
echo "== (2) commercial gate selfcheck =="
bin/p1_commercial_gate_selfcheck_p1_v1.sh

echo
echo "== (3) build boss bundle (latest RID) =="
bin/p1_make_boss_bundle_from_latest_rid_v1.sh

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
OUT_DIR="$(ls -1dt out_ci/BOSS_BUNDLE_${RID}_* 2>/dev/null | head -n1 || true)"

echo
echo "================== READY FOR COMMERCIAL (P1) =================="
echo "[RID]   $RID"
echo "[BASE]  $BASE"
echo "[REPORT] $BASE/api/vsp/run_file?rid=$RID&name=reports%2Findex.html"
echo "[BUNDLE] ${OUT_DIR:-"(not found)"}"
echo "==============================================================="
