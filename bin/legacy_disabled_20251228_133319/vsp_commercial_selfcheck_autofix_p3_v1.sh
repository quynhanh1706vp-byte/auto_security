#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
OUTROOT="out_ci"
N_STAB="${1:-120}"   # vòng stability (nhanh). tăng nếu muốn
TS="$(date +%Y%m%d_%H%M%S)"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need_cmd curl; need_cmd python3; need_cmd tar; need_cmd sha256sum

log "== VSP COMMERCIAL SELFCHECK+AUTOFIX P3 =="
log "[BASE]=$BASE [N_STAB]=$N_STAB"

# 0) ensure UI up (light)
code="$(curl -sS -m 4 -o /dev/null -w '%{http_code}' "$BASE/vsp4" || echo 000)"
if [ "$code" != "200" ]; then
  log "[WARN] /vsp4 not 200 ($code) -> hard reset 8910"
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh || true
fi

# 1) 5 tabs smoke
log "== smoke 5 tabs =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh | tee "$OUTROOT/p3_ui_5tabs_${TS}.log"

# 2) stability quick
log "== stability quick =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_smoke_p0_v1.sh "$N_STAB" | tee "$OUTROOT/p3_stability_${TS}.log"

# 3) gate P2 (creates COMMERCIAL_* evidence)
log "== gate P2 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_commercial_autofix_gate_p2_v1.sh | tee "$OUTROOT/p3_gate_${TS}.log"

# 4) pack audit bundle
log "== pack audit bundle =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v1.sh | tee "$OUTROOT/p3_pack_audit_${TS}.log"

# locate latest audit bundle + sha file
AUDIT_TGZ="$(ls -1t "$OUTROOT"/AUDIT_BUNDLE_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "${AUDIT_TGZ:-}" ] || { echo "[ERR] cannot find AUDIT_BUNDLE_*.tgz"; exit 3; }
BNAME="$(basename "$AUDIT_TGZ" .tgz)"
SHAF="$OUTROOT/${BNAME}.SHA256SUMS.txt"
[ -s "$SHAF" ] || { echo "[ERR] missing sha file: $SHAF"; exit 4; }

# 5) verify sha
log "== verify sha =="
( cd "$OUTROOT" && sha256sum -c "$(basename "$SHAF")" ) | tee "$OUTROOT/p3_verify_sha_${TS}.log"

# 6) unpack + validate
TMP="$OUTROOT/__TMP_AUDIT_${TS}"
rm -rf "$TMP" && mkdir -p "$TMP"
tar -xzf "$AUDIT_TGZ" -C "$TMP"
ROOT="$TMP/$BNAME"
[ -d "$ROOT" ] || { echo "[ERR] unpacked root missing: $ROOT"; exit 5; }

req=(
  "$ROOT/meta/VERSION.txt"
  "$ROOT/ui/latest_rid_v1.json"
  "$ROOT/ui/dashboard_commercial_v2.json"
  "$ROOT/checks/ui_5tabs_smoke.txt"
)
missing=0
for f in "${req[@]}"; do
  if [ ! -s "$f" ]; then
    echo "[FAIL] missing/empty: $f"
    missing=$((missing+1))
  else
    echo "[OK] $f"
  fi
done

# parse RID/RUN_DIR from bundled latest_rid
RID="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("rid") or j.get("ci_rid") or "")' "$ROOT/ui/latest_rid_v1.json" 2>/dev/null || true)"
RUN_DIR="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("ci_run_dir") or "")' "$ROOT/ui/latest_rid_v1.json" 2>/dev/null || true)"
echo "[BUNDLED] RID=$RID"
echo "[BUNDLED] RUN_DIR=$RUN_DIR"

# dashboard ok?
DOK="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print("1" if j.get("ok") else "0")' "$ROOT/ui/dashboard_commercial_v2.json" 2>/dev/null || echo 0)"
if [ "$DOK" != "1" ]; then
  echo "[WARN] dashboard_commercial_v2.json ok=false (non-fatal for pack, but should be fixed)"
fi

# report tgz exists in bundle?
RPT_TGZ="$(ls -1 "$ROOT/run"/*__REPORT.tgz 2>/dev/null | head -n1 || true)"
if [ -z "${RPT_TGZ:-}" ]; then
  echo "[WARN] report tgz not present inside audit bundle (will try autofix if RUN_DIR valid)"
else
  echo "[OK] report tgz in bundle: $(basename "$RPT_TGZ")"
fi

# verify_report_sha.json check (if present)
VJ="$ROOT/run/verify_report_sha.json"
VOK="1"
if [ -s "$VJ" ]; then
  VOK="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print("1" if j.get("ok") and j.get("returncode",0)==0 else "0")' "$VJ" 2>/dev/null || echo 0)"
  echo "[CHECK] verify_report_sha.json ok=$VOK"
fi

# scan UI error log for exceptions (non-blocking but signal)
ELOG="$ROOT/ui/ui_8910.error.log"
if [ -s "$ELOG" ]; then
  hits="$(grep -E -n "Traceback|Exception|ERROR" "$ELOG" | tail -n 5 || true)"
  if [ -n "${hits:-}" ]; then
    echo "[WARN] ui_8910.error.log has error keywords (last 5):"
    echo "$hits"
  else
    echo "[OK] ui_8910.error.log no obvious Traceback/Exception/ERROR"
  fi
else
  echo "[INFO] ui_8910.error.log not bundled (ok)"
fi

# ---- AUTOFIX 1 lần nếu report missing/sha fail ----
if { [ "$VOK" = "0" ] || [ -z "${RPT_TGZ:-}" ]; } && [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ]; then
  echo "== AUTOFIX: rebuild report tgz + repack audit (one retry) =="
  /home/test/Data/SECURITY_BUNDLE/bin/pack_report.sh "$RUN_DIR" || true
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v1.sh | tee "$OUTROOT/p3_repack_audit_${TS}.log"

  AUDIT_TGZ2="$(ls -1t "$OUTROOT"/AUDIT_BUNDLE_*.tgz 2>/dev/null | head -n1 || true)"
  B2="$(basename "$AUDIT_TGZ2" .tgz)"
  SHAF2="$OUTROOT/${B2}.SHA256SUMS.txt"
  echo "== verify sha (repack) =="
  ( cd "$OUTROOT" && sha256sum -c "$(basename "$SHAF2")" ) || true
  echo "[OK] repacked: $AUDIT_TGZ2"
fi

echo "== SUMMARY =="
echo "[AUDIT_TGZ]=$AUDIT_TGZ"
echo "[SHA]=$SHAF"
echo "[TMP]=$TMP"
if [ "$missing" -eq 0 ]; then
  echo "[PASS] audit bundle core files present"
else
  echo "[FAIL] missing_core_files=$missing"
  exit 6
fi
