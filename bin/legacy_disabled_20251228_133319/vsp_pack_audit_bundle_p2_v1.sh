#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUTROOT="out_ci"
mkdir -p "$OUTROOT"

# ---- (1) resolve latest RID + RUN_DIR ----
J="$OUTROOT/_latest_rid_${TS}.json"
curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS" > "$J" || true
RID="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("rid") or j.get("ci_rid") or "")' "$J" 2>/dev/null || true)"
RUN_DIR="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("ci_run_dir") or "")' "$J" 2>/dev/null || true)"
[ -n "${RID:-}" ] || RID="RID_UNKNOWN"
[ -n "${RUN_DIR:-}" ] || RUN_DIR="RUN_DIR_UNKNOWN"

BNAME="AUDIT_BUNDLE_${RID}_${TS}"
BDIR="$OUTROOT/$BNAME"
mkdir -p "$BDIR"/{meta,ui,run,checks}

echo "== VSP AUDIT BUNDLE P2 ==" | tee "$BDIR/meta/build.log"
echo "[BASE]=$BASE"            | tee -a "$BDIR/meta/build.log"
echo "[RID]=$RID"              | tee -a "$BDIR/meta/build.log"
echo "[RUN_DIR]=$RUN_DIR"      | tee -a "$BDIR/meta/build.log"
echo "[BDIR]=$BDIR"            | tee -a "$BDIR/meta/build.log"

# ---- (2) VERSION / provenance (ISO-style) ----
{
  echo "STAMP=$(date +%Y-%m-%dT%H:%M:%S%z)"
  echo "HOST=$(hostname)"
  echo "USER=$(whoami)"
  echo "BASE=$BASE"
  echo "RID=$RID"
  echo "RUN_DIR=$RUN_DIR"
  echo "UI_DIR=$(pwd)"
  echo "BUNDLE=/home/test/Data/SECURITY_BUNDLE"
  echo "JS_SHA256=$(sha256sum static/js/vsp_bundle_commercial_v2.js 2>/dev/null | awk '{print $1}')"
  echo "APP_SHA256=$(sha256sum vsp_demo_app.py 2>/dev/null | awk '{print $1}')"
  echo "GUNICORN_PIDFILE=out_ci/ui_8910.pid"
} > "$BDIR/meta/VERSION.txt"

# ---- (3) collect latest COMMERCIAL gate folder (if exists) ----
COMM_LATEST="$(ls -1dt "$OUTROOT"/COMMERCIAL_* 2>/dev/null | head -n1 || true)"
if [ -n "${COMM_LATEST:-}" ] && [ -d "$COMM_LATEST" ]; then
  echo "[OK] COMMERCIAL_LATEST=$COMM_LATEST" | tee -a "$BDIR/meta/build.log"
  cp -af "$COMM_LATEST"/* "$BDIR/ui/" 2>/dev/null || true
else
  echo "[WARN] no COMMERCIAL_* folder found under $OUTROOT" | tee -a "$BDIR/meta/build.log"
fi

# always keep latest_rid json
cp -f "$J" "$BDIR/ui/latest_rid_v1.json" 2>/dev/null || true

# ---- (4) snapshot dashboards + core APIs (evidence) ----
curl -sS "$BASE/api/vsp/dashboard_commercial_v2?ts=$TS" > "$BDIR/ui/dashboard_commercial_v2.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/dashboard_commercial_v1?ts=$TS" > "$BDIR/ui/dashboard_commercial_v1.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/findings_latest_v1?limit=3&ts=$TS" > "$BDIR/ui/findings_latest_3.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/rule_overrides_v1?ts=$TS" > "$BDIR/ui/rule_overrides_dump.json" 2>/dev/null || true

# ---- (5) attach UI logs (ops evidence) ----
cp -f "$OUTROOT/ui_8910.error.log"  "$BDIR/ui/ui_8910.error.log" 2>/dev/null || true
cp -f "$OUTROOT/ui_8910.access.log" "$BDIR/ui/ui_8910.access.log" 2>/dev/null || true

# ---- (6) ensure report tgz exists for RUN_DIR; pack if missing ----
if [ -d "$RUN_DIR" ]; then
  OUTNAME="$(basename "$RUN_DIR")__REPORT.tgz"
  RPTTGZ="$RUN_DIR/$OUTNAME"

  if [ ! -s "$RPTTGZ" ]; then
    echo "[INFO] report tgz missing -> running pack_report.sh on RUN_DIR" | tee -a "$BDIR/meta/build.log"
    /home/test/Data/SECURITY_BUNDLE/bin/pack_report.sh "$RUN_DIR" >/dev/null || true
  fi

  if [ -s "$RPTTGZ" ]; then
    cp -f "$RPTTGZ" "$BDIR/run/" || true
    # also copy run sha sums if present
    [ -f "$RUN_DIR/SHA256SUMS.txt" ] && cp -f "$RUN_DIR/SHA256SUMS.txt" "$BDIR/run/SHA256SUMS.txt" || true
  else
    echo "[WARN] still no report tgz at $RPTTGZ" | tee -a "$BDIR/meta/build.log"
  fi

  # verify sha via API if possible (nice evidence)
  QRD="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RUN_DIR" 2>/dev/null || true)"
  if [ -n "${QRD:-}" ]; then
    curl -sS "$BASE/api/vsp/verify_report_sha_v1?run_dir=$QRD&ts=$TS" > "$BDIR/run/verify_report_sha.json" 2>/dev/null || true
    curl -sS -I "$BASE/api/vsp/export_report_tgz_v1?run_dir=$QRD&ts=$TS" > "$BDIR/run/export_report_tgz_head.txt" 2>/dev/null || true
  fi
fi

# ---- (7) attach 5-tabs smoke output (ops evidence) ----
if [ -x "/home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh" ]; then
  /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_5tabs_smoke_p2_v1.sh > "$BDIR/checks/ui_5tabs_smoke.txt" 2>&1 || true
fi

# ---- (8) pack final AUDIT tgz + SHA256SUMS (+ minisign optional) ----
TGZ="$OUTROOT/${BNAME}.tgz"
tar -czf "$TGZ" -C "$OUTROOT" "$BNAME"
echo "[OK] packed: $TGZ" | tee -a "$BDIR/meta/build.log"

( cd "$OUTROOT" && sha256sum "$(basename "$TGZ")" > "${BNAME}.SHA256SUMS.txt" )
echo "[OK] sha256: $OUTROOT/${BNAME}.SHA256SUMS.txt" | tee -a "$BDIR/meta/build.log"

if [ "${SIGN:-0}" = "1" ]; then
  SEC="${KEY_SEC:-$HOME/.minisign/mykey.sec}"
  PUB="${KEY_PUB:-$HOME/.minisign/mykey.pub}"
  if command -v minisign >/dev/null 2>&1 && [ -s "$SEC" ] && [ -s "$PUB" ]; then
    ( cd "$OUTROOT" && minisign -Sm "${BNAME}.SHA256SUMS.txt" -s "$SEC" -t "VSP Audit bundle $BNAME" ) || true
    echo "[OK] minisign: $OUTROOT/${BNAME}.SHA256SUMS.txt.minisig" | tee -a "$BDIR/meta/build.log"
  else
    echo "[WARN] SIGN=1 but minisign/key missing -> skipped" | tee -a "$BDIR/meta/build.log"
  fi
fi

echo "== DONE ==" | tee -a "$BDIR/meta/build.log"
echo "[OPEN] $TGZ"
echo "[HINT] Verify:"
echo "  cd \"$OUTROOT\" && sha256sum -c \"${BNAME}.SHA256SUMS.txt\""
echo "  # if minisign:"
echo "  minisign -Vm \"${BNAME}.SHA256SUMS.txt\" -p \"\${KEY_PUB:-$HOME/.minisign/mykey.pub}\""
