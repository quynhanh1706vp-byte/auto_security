#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need sort; need tail; need awk; need tar; need sha256sum; need find

OUT_ABS="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases"
mkdir -p "$OUT_ABS"

TS="$(date +%Y%m%d_%H%M%S)"
DROP="$OUT_ABS/VSP_COMMERCIAL_DROP_${TS}.tgz"
MAN="$OUT_ABS/VSP_COMMERCIAL_DROP_${TS}.MANIFEST.txt"

pick_latest_abs(){
  local pat="$1"
  ls -1 "$OUT_ABS"/$pat 2>/dev/null | sort | tail -n 1 || true
}

UI="$(pick_latest_abs 'VSP_UI_RELEASE_*.tgz')"
EV="$(pick_latest_abs 'VSP_UI_EVIDENCE_*.tgz')"

[ -n "${UI:-}" ] || { echo "[ERR] missing UI release in $OUT_ABS"; exit 2; }
[ -n "${EV:-}" ] || { echo "[ERR] missing evidence tgz in $OUT_ABS"; exit 2; }

REPORT=""
for root in \
  /home/test/Data/SECURITY_BUNDLE/out \
  /home/test/Data/SECURITY_BUNDLE/out_ci \
  /home/test/Data/SECURITY-10-10-v4/out_ci \
  /home/test/Data/SECURITY_BUNDLE/ui/out_ci
do
  [ -d "$root" ] || continue
  cand="$(find "$root" -maxdepth 4 -type f \( -name '*__REPORT.tgz' -o -name '*pack_report*.tgz' -o -name '*REPORT*.tgz' -o -name '*report*.tgz' \) 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "$cand" ]; then REPORT="$cand"; break; fi
done

echo "== [A] build manifest =="
{
  echo "VSP COMMERCIAL DROP"
  echo "ts=$TS"
  echo "ui_release=$UI"
  echo "ui_release_sha=$(sha256sum "$UI" | awk '{print $1}')"
  echo "evidence=$EV"
  echo "evidence_sha=$(sha256sum "$EV" | awk '{print $1}')"
  if [ -n "$REPORT" ]; then
    echo "report_bundle=$REPORT"
    echo "report_bundle_sha=$(sha256sum "$REPORT" | awk '{print $1}')"
  else
    echo "report_bundle=NONE"
  fi
  echo "notes="
  echo " - Includes UI snapshot + evidence gate logs + endpoint snapshots."
  echo " - Use evidence/gate_output.txt to reproduce readiness verdict."
} | tee "$MAN"

echo "== [B] pack drop =="
args=()
args+=( -C "$(dirname "$UI")" "$(basename "$UI")" )
args+=( -C "$(dirname "$EV")" "$(basename "$EV")" )
args+=( -C "$(dirname "$MAN")" "$(basename "$MAN")" )
if [ -n "$REPORT" ]; then
  args+=( -C "$(dirname "$REPORT")" "$(basename "$REPORT")" )
fi

tar -czf "$DROP" "${args[@]}"
sha256sum "$DROP" | tee "$DROP.sha256"

echo "== [DONE] =="
echo "DROP=$DROP"
