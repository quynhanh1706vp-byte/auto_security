#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need sort; need head; need tail; need awk; need tar; need sha256sum; need find; need sed

OUT="out_ci/releases"
mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
DROP="$OUT/VSP_COMMERCIAL_DROP_${TS}.tgz"
MAN="$OUT/VSP_COMMERCIAL_DROP_${TS}.MANIFEST.txt"

pick_latest(){
  local pat="$1"
  ls -1 "$OUT"/$pat 2>/dev/null | sort | tail -n 1
}

UI="$(pick_latest 'VSP_UI_RELEASE_*.tgz')"
EV="$(pick_latest 'VSP_UI_EVIDENCE_*.tgz')"

[ -n "${UI:-}" ] || { echo "[ERR] missing UI release in $OUT"; exit 2; }
[ -n "${EV:-}" ] || { echo "[ERR] missing evidence tgz in $OUT"; exit 2; }

# best-effort: locate a "report bundle" from SECURITY_BUNDLE if exists
REPORT=""
for root in \
  /home/test/Data/SECURITY_BUNDLE/out \
  /home/test/Data/SECURITY_BUNDLE/out_ci \
  /home/test/Data/SECURITY-10-10-v4/out_ci \
  /home/test/Data/SECURITY_BUNDLE/ui/out_ci
do
  [ -d "$root" ] || continue
  cand="$(find "$root" -maxdepth 4 -type f \( -name '*pack_report*.tgz' -o -name '*REPORT*.tgz' -o -name '*report*.tgz' \) 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "$cand" ]; then REPORT="$cand"; break; fi
done

echo "== [A] build manifest =="
{
  echo "VSP COMMERCIAL DROP"
  echo "ts=$TS"
  echo "ui_release=$(basename "$UI")"
  echo "ui_release_sha=$(sha256sum "$UI" | awk '{print $1}')"
  echo "evidence=$(basename "$EV")"
  echo "evidence_sha=$(sha256sum "$EV" | awk '{print $1}')"
  if [ -n "$REPORT" ]; then
    echo "report_bundle=$REPORT"
    echo "report_bundle_sha=$(sha256sum "$REPORT" | awk '{print $1}')"
  else
    echo "report_bundle=NONE"
  fi
  echo "notes="
  echo " - This drop includes UI snapshot + evidence gate logs + endpoint snapshots."
  echo " - Run gate script inside evidence to reproduce readiness verdict."
} | tee "$MAN"

echo "== [B] pack drop =="
tar -czf "$DROP" \
  -C "$OUT" "$(basename "$UI")" \
  -C "$OUT" "$(basename "$EV")" \
  -C "$OUT" "$(basename "$MAN")" \
  $( [ -n "$REPORT" ] && echo "-C / $(echo "$REPORT" | sed 's#^/##')" )

sha256sum "$DROP" | tee "$DROP.sha256"

echo "== [DONE] =="
echo "DROP=$DROP"
